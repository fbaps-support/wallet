package Wallet;

use strict;
use DBI;
use MIME::Base64;

use Digest::SHA;
use Crypt::CBC;
use Crypt::Rijndael;
use Crypt::OpenSSL::Random;
use Crypt::OpenSSL::RSA;

sub new
{
	my ($self, $dbfile, $create_with_this_user) = @_;

	$self = {
		db => undef,
		ivlen => 16,
		pkbits => 2048,
		err => "No error"
	};
	bless $self;

	if (defined($create_with_this_user))
	{
		return "won't overwrite an existing database file"
			if (-e $dbfile);
		$self->{db} = DBI->connect("dbi:SQLite:dbname=$dbfile","","", {
			AutoCommit => 1,
			sqlite_use_immediate_transaction => 1,
		});
		return "Failed to create database: $DBI::errstr"
			unless (defined($self->{db}));

		if (!$self->exec(q{
			CREATE TABLE users (
				ID INTEGER PRIMARY KEY AUTOINCREMENT,
				username VARCHAR(255),
				publickey TEXT,
				privatekey TEXT,
				useradmin INTEGER DEFAULT 0,
				emergencyadmin INTEGER DEFAULT 0,
				UNIQUE(username)
			)
		}))
		{
			$self->{db} = undef;
			unlink($dbfile);
			return $DBI::errstr;
		}
		if (!$self->exec(q{
			INSERT INTO users (username, useradmin)
			VALUES (?, 1)
		}, $create_with_this_user))
		{
			$self->{db} = undef;
			unlink($dbfile);
			return $DBI::errstr;
		}
		if (!$self->exec(q{
			CREATE TABLE credentials (
				ID INTEGER PRIMARY KEY AUTOINCREMENT,
				description TEXT,
				last_changed INTEGER,
				expiry_weeks INTEGER,
				insecure INTEGER DEFAULT 0,
				encrypted TEXT
			)
		}))
		{
			$self->{db} = undef;
			unlink($dbfile);
			return $DBI::errstr;
		}
		if (!$self->exec(q{
			CREATE TABLE tags (
				ID INTEGER,
				tag VARCHAR(255)
			)
		}))
		{
			$self->{db} = undef;
			unlink($dbfile);
			return $DBI::errstr;
		}
		if (!$self->exec(q{
			CREATE TABLE access (
				ID INTEGER,
				username VARCHAR(255),
				grantedby VARCHAR(255),
				is_owner INTEGER,
				aeskey VARCHAR(255),
				UNIQUE(ID, username)
			)
		}))
		{
			$self->{db} = undef;
			unlink($dbfile);
			return $DBI::errstr;
		}
	}
	else
	{
		return "database file not found"
			unless (-e $dbfile);
		$self->{db} = DBI->connect("dbi:SQLite:dbname=$dbfile","","", {
			AutoCommit => 1,
			sqlite_use_immediate_transaction => 1,
		});
		return "Failed to connect to database: $DBI::errstr"
			unless (defined($self->{db}));
	}
	return $self;
}

sub err
{
	my ($self) = @_;
	return $self->{err};
}

# Create a user with no keys. A subsequent call
# to setuserpassword should be made to initialise the
# keys. Until this is done, no wallet entries can
# be granted to the user.
#
# This function has a getout clause for access-control
# checking. If the function is called with only
# one argument then it's assumed that the creator need
# not be checked. If called with two arguments then 
# the creator must be a user administrator.
#
sub createuser
{
	my ($self, $username, $creator) = @_;

	if ($username !~ /^\s*(\S+)\s*$/)
	{
		$self->{err} = "username was blank";
		return 0;
	}
	$username = $1;

	if (@_ != 2)
	{
		my $user = $self->getuser($creator);
		if (!defined($user) || !$user->{useradmin})
		{
			$self->{err} = "not a user-administrator";
			return 0;
		}
	}

	my $user = $self->getuser($username);
	if (defined($user))
	{
		$self->{err} = "user already exists";
		return 0;
	}

	if (!$self->exec(q{
		INSERT INTO users (username) VALUES (?)
	}, $username))
	{
		return 0;
	}
	return 1;
}

# Modify a user's admin credentials
sub modifyuser
{
	my ($self, $username, $adminusername, $isuseradmin, $isemergencyadmin) = @_;

	if ($isuseradmin !~ /^\s*[01]\s*$/)
	{
		$self->{err} = "invalid isuseradmin value (must be 0 or 1)";
		return 0;
	}
	if ($isemergencyadmin !~ /^\s*[01]\s*$/)
	{
		$self->{err} = "invalid isemergencyadmin value (must be 0 or 1)";
		return 0;
	}
	my $user = $self->getuser($adminusername);
	if (!defined($user) || !$user->{useradmin})
	{
		$self->{err} = "not a user-administrator";
		return 0;
	}
	$user = $self->getuser($username);
	if (!defined($user))
	{
		$self->{err} = "user not found";
		return 0;
	}

	if (!$self->exec(q{
		UPDATE users
		SET useradmin=?, emergencyadmin=?
		WHERE username=?
	}, $isuseradmin, $isemergencyadmin, $username))
	{
		return 0;
	}
	return 1;
}

# Delete a user.
sub deleteuser
{
	my ($self, $username, $adminusername) = @_;

	my $user = $self->getuser($adminusername);
	if (!defined($user) || !$user->{useradmin})
	{
		$self->{err} = "not a user-administrator";
		return 0;
	}
	if (!$self->begin_work)
	{
		$self->{err} = "failed to start a transaction";
		return 0;
	}

	# Mark all credentials this user had access to as insecure.
	if (!$self->exec(q{
		UPDATE credentials
		SET insecure=1
		WHERE ID IN (
			SELECT ID
			FROM access
			WHERE username=?
		)
	}))
	{
		$self->{err} = "failed to update credentials";
		$self->rollback;
		return 0;
	}

	# Delete from the access list.
	if (!$self->exec(q{
		DELETE FROM access
		WHERE username=?
	}, $username))
	{
		$self->rollback;
		$self->{err} = "failed to delete access";
		return 0;
	}

	# Delete from the user list.
	if (!$self->exec(q{
		DELETE FROM users
		WHERE username=?
	}, $username))
	{
		$self->rollback;
		$self->{err} = "failed to delete user";
		return 0;
	}
	return $self->commit;
}

# Return details about a stored credential by ID.
sub credentialdetails
{
	my ($self, $id) = @_;
	my $details = $self->getrow(q{
		SELECT *
		FROM credentials
		WHERE ID=?
	}, $id);
	if (!defined($details))
	{
		return undef;
	}
	$details->{owners} = [];
	$details->{users} = [];
	$details->{tags} = [];
	my $q = $self->{db}->prepare(q{
		SELECT users.ID, users.username, access.is_owner
		FROM access
		LEFT JOIN users USING (username)
		WHERE access.ID=?
	});
	if (!defined($q) || !$q->execute($id))
	{
		$self->{err} = $DBI::errstr;
		return undef;
	}
	while (defined(my $row = $q->fetchrow_hashref))
	{
		push(@{$details->{users}}, $row);
		if ($row->{is_owner})
		{
			push(@{$details->{owners}}, $row);
		}
	}
	$q->finish;
	$q = $self->{db}->prepare(q{
		SELECT tag
		FROM tags
		WHERE ID=?
		ORDER BY tag COLLATE NOCASE
	});
	if (!defined($q) || !$q->execute($id))
	{
		$self->{err} = $DBI::errstr;
		return undef;
	}
	while (defined(my $row = $q->fetchrow_hashref))
	{
		push(@{$details->{tags}}, $row->{tag});
	}
	$q->finish;
	return $details;
}

# Return a list of credentials that a user has access to.
sub hasaccess
{
	my ($self, $username, $onlyowned) = @_;
	$onlyowned = 0 unless defined($onlyowned);

	my $q = $self->{db}->prepare(q{
		SELECT credentials.*, access.grantedby, access.is_owner, access.aeskey
		FROM access
		LEFT JOIN credentials USING (ID)
		WHERE access.username=?
		ORDER BY credentials.description COLLATE NOCASE
	});
	if (!defined($q) || !$q->execute($username))
	{
		$self->{err} = $DBI::errstr;
		return undef;
	}
	my @hasaccess = ();
	while (defined(my $row = $q->fetchrow_hashref))
	{
		if (!$onlyowned || ($onlyowned && $row->{is_owner}))
		{
			my $t = $self->{db}->prepare(q{
				SELECT tag
				FROM tags
				WHERE ID = ?
				ORDER BY tag COLLATE NOCASE
			});
			if (!defined($t) || !$t->execute($row->{ID}))
			{
				$self->{err} = $DBI::errstr;
				$q->finish;
				return undef;
			}
			$row->{tags} = [];
			while (defined(my $tag = $t->fetchrow_hashref))
			{
				push(@{$row->{tags}}, $tag->{tag});
			}
			$t->finish;
			push(@hasaccess, $row);
		}
	}
	return \@hasaccess;
}

# Return a list of users.
sub userlist
{
	my ($self) = @_;
	my $q = $self->{db}->prepare(q{
		SELECT *
		FROM users
		ORDER BY username COLLATE NOCASE
	});
	if (!defined($q) || !$q->execute())
	{
		$self->{err} = $DBI::errstr;
		return undef;
	}
	my @users = ();
	while (defined(my $row = $q->fetchrow_hashref))
	{
		push(@users, $row);
	}
	return \@users;
}

# Re-password the private key of a user.
# If the user already has a private key then $oldpassword
# needs to be supplied to allow decryption of the private key. 
# If not then a new private/public key pair is created.
sub setuserpassword
{
	my ($self, $username, $newpassword, $oldpassword) = @_;

	my $user = $self->getuser($username);
	if (!defined($user))
	{
		$self->{err} = "user not found";
		return 0;
	}

	if (!defined($user->{publickey}))
	{
		my ($publickey, $privatekey) = $self->generate_keys($newpassword);
		if (!$self->exec(q{
			UPDATE users 
			SET publickey=?, privatekey=?
			WHERE username=?
		}, $publickey, $privatekey, $username))
		{
			return 0;
		}
	}
	else
	{
		if (!defined($oldpassword))
		{
			$self->{err} = "user has a key but their password was not supplied";
			return 0;
		}

		my $privatekey = $self->aes_decrypt($user->{privatekey}, $oldpassword);
		if ($privatekey !~ /^-----BEGIN RSA PRIVATE KEY-----/)
		{
			$self->{err} = "old password incorrect";
			return 0;
		}

		($privatekey, $newpassword) = $self->aes_encrypt($privatekey, $newpassword);
		if (!$self->exec(q{
			UPDATE users 
			SET privatekey=?
			WHERE username=?
		}, $privatekey, $username))
		{
			return 0;
		}
	}
	return 1;
}

# Null out the public/private key of a user and all encrypted keys
# for that user. Use this when a user has forgotten their password.
# 
sub resetuserpassword
{
	my ($self, $username, $adminusername) = @_;

	my $user = $self->getuser($adminusername);
	if (!defined($user) || !$user->{useradmin})
	{
		$self->{err} = "not a user-administrator";
		return 0;
	}
	if (!$self->begin_work)
	{
		return 0;
	}

	# Null out aes keys in the access list for the user.
	if (!$self->exec(q{
		UPDATE access
		SET aeskey=NULL
		WHERE username=?
	}, $username))
	{
		$self->rollback;
		return 0;
	}

	# Null out the public/private key pair in the 
	# user list.
	if (!$self->exec(q{
		UPDATE users
		SET publickey=NULL, privatekey=NULL
		WHERE username=?
	}, $username))
	{
		$self->rollback;
		return 0;
	}
	return $self->commit;
}

# Create a credential, owned by $username. Returns the ID or
# 0 for failure.
sub createcredential
{
	my ($self, $description, $expiry_weeks, $credential, $username) = @_;
	my $user = $self->getuser($username);
	if (!defined($user))
	{
		$self->{err} = "user not found";
		return 0;
	}
	if ($expiry_weeks !~ /^\s*(\d+|)\s*$/)
	{
		$self->{err} = "expiry must be blank or a positive integer";
		return 0;
	}
	$expiry_weeks = $1;

	# Generate an AES key and encrypt with it.
	my ($encrypted, $aeskey) = $self->aes_encrypt($credential);
	my $enckey = $self->rsa_encrypt($aeskey, $user->{publickey});

	if (!$self->begin_work)
	{
		return 0;
	}
	if (!$self->exec(q{
		INSERT INTO credentials (description, expiry_weeks, last_changed, encrypted)
		VALUES (?, ?, ?, ?)
	}, $description, $expiry_weeks, time, $encrypted))
	{
		$self->rollback;
		return 0;
	}
	my $id = $self->{db}->last_insert_id(undef, undef, undef, undef);
	if (!$self->exec(q{
		INSERT INTO access (ID, username, grantedby, is_owner, aeskey)
		VALUES (?, ?, ?, 1, ?)
	}, $id, $username, $username, $enckey))
	{
		$self->rollback;
		return 0;
	}
	if (!$self->commit)
	{
		return 0;
	}
	return $id;
}

# Change credential properties.
sub changecredentialproperties
{
	my ($self, $id, $username, $expiry_weeks, $description) = @_;
	if (!$self->is_owner($username, $id))
	{
		$self->{err} = "not an owner of this credential";
		return 0;
	}
	if ($expiry_weeks !~ /^\s*(\d+|)\s*$/)
	{
		$self->{err} = "expiry must be blank or a positive integer";
		return 0;
	}
	$expiry_weeks = $1;

	return $self->exec(q{
		UPDATE credentials
		SET expiry_weeks=?, description=?
		WHERE ID=?
	}, $expiry_weeks, $description, $id)
}

# Change credential tags.
sub changecredentialtags
{
	my ($self, $id, $username, @tags) = @_;
	if (!$self->is_owner($username, $id))
	{
		$self->{err} = "not an owner of this credential";
		return 0;
	}

	if (!$self->begin_work)
	{
		return 0;
	}
	if (!$self->exec(q{
		DELETE FROM tags
		WHERE ID = ?
	}, $id))
	{
		$self->rollback;
		return 0;
	}
	foreach my $tag (@tags)
	{
		next if ($tag eq "");
		if ($tag !~ /^[a-z0-9_-]+$/)
		{
			$self->rollback;
			$self->{err} = "'$tag': tags must only contain lower case letters, digits or - or _";
			return 0;
		}
		if (!$self->exec(q{
			INSERT INTO tags (ID, tag)
			VALUES (?, ?)
		}, $id, $tag))
		{
			$self->rollback;
			return 0;
		}
	}
	if (!$self->commit)
	{
		return 0;
	}
	return 1;
}

# Get all currently existing tags
sub gettaglist
{
	my ($self) = @_;
	my $q = $self->{db}->prepare(q{
		SELECT DISTINCT tag
		FROM tags
	});
	if (!defined($q) || !$q->execute())
	{
		$self->{err} = $DBI::errstr;
		return undef;
	}
	my @tags = ();
	while (defined(my $row = $q->fetchrow_hashref))
	{
		push(@tags, $row->{tag});
	}
	return \@tags;
}

# Delete a credential
sub deletecredential
{
	my ($self, $id, $owner) = @_;
	if (!$self->is_owner($owner, $id))
	{
		$self->{err} = "not an owner of this credential";
		return 0;
	}
	if (!$self->begin_work)
	{
		return 0;
	}
	if (!$self->exec(q{
		DELETE FROM access
		WHERE ID=?
	}, $id))
	{
		$self->rollback;
		return 0;
	}
	if (!$self->exec(q{
		DELETE FROM tags
		WHERE ID=?
	}, $id))
	{
		$self->rollback;
		return 0;
	}
	if (!$self->exec(q{
		DELETE FROM credentials
		WHERE ID=?
	}, $id))
	{
		$self->rollback;
		return 0;
	}
	return $self->commit;
}

# Change a credential
sub changecredential
{
	my ($self, $id, $owner, $newcredential) = @_;
	if (!$self->is_owner($owner, $id))
	{
		$self->{err} = "not owner of credential";
		return 0;
	}

	my ($enc, $key) = $self->aes_encrypt($newcredential);

	if (!$self->begin_work)
	{
		return 0;
	}

	# Update the encrypted credential.
	if (!$self->exec(q{
		UPDATE credentials
		SET last_changed=?, insecure=0, encrypted=?
		WHERE ID=?
	}, time, $enc, $id))
	{
		return 0;
	}

	# Now, for each user, RSA-encrypt the AES key to that credential.
	my $q = $self->{db}->prepare(q{
		SELECT username
		FROM access
		WHERE ID=?
	});
	if (!defined($q) || !$q->execute($id))
	{
		$self->{err} = $DBI::errstr;
		$self->rollback;
		return 0;
	}
	while (defined(my $row = $q->fetchrow_hashref))
	{
		my $user = $self->getuser($row->{username});
		if (defined($user) && defined($user->{publickey}))
		{
			my $enckey = $self->rsa_encrypt($key, $user->{publickey});

			if (!$self->exec(q{
				UPDATE access
				SET aeskey=?
				WHERE ID=?
				AND username=?
			}, $enckey, $id, $row->{username}))
			{
				$self->rollback;
				return 0;
			}
		}
	}

	return $self->commit;
}

# Grant access to a credential to a user.
sub grantcredential
{
	my ($self, $id, $owner, $ownerpassword, $username) = @_;
	if (!$self->is_owner($owner, $id))
	{
		$self->{err} = "not owner of credential";
		return 0;
	}
	my $user = $self->getuser($username);
	if (!defined($user))
	{
		$self->{err} = "user not found";
		return 0;
	}
	if (!defined($user->{publickey}))
	{
		$self->{err} = "user has not set a password yet";
		return 0;
	}

	my $key = $self->getkey($id, $owner, $ownerpassword);
	if (!defined($key))
	{
		$self->{err} = "password incorrect";
		return 0;
	}

	if (!$self->begin_work)
	{
		return 0;
	}
	if (!$self->exec(q{
		DELETE FROM access
		WHERE ID=?
		AND username=?
	}, $id, $username))
	{
		return 0;
	}
	my $encrypted = $self->rsa_encrypt($key, $user->{publickey});
	if (!$self->exec(q{
		INSERT INTO access (ID, username, grantedby, is_owner, aeskey)
		VALUES (?, ?, ?, 0, ?)
	}, $id, $username, $owner, $encrypted))
	{
		return 0;
	}
	return $self->commit;
}

# Revoke access to a credential from a user.
sub revokecredential
{
	my ($self, $id, $owner, $username) = @_;

	if (!$self->is_owner($owner, $id))
	{
		$self->{err} = "not owner of credential";
		return 0;
	}
	if (!$self->begin_work)
	{
		return 0;
	}
	
	# Mark that credential as insecure.
	if (!$self->exec(q{
		UPDATE credentials
		SET insecure=1
		WHERE ID=?
	}, $id))
	{
		$self->rollback;
		return 0;
	}
	if (!$self->exec(q{
		DELETE FROM access
		WHERE ID=?
		AND username=?
	}, $id, $username))
	{
		$self->rollback;
		return 0;
	}
	return $self->commit;
}

# Set the owner flag on a credential for a user.
sub setownerflag
{
	my ($self, $id, $owner, $username, $flag) = @_;
	if (!$self->is_owner($owner, $id))
	{
		$self->{err} = "not owner of credential";
		return 0;
	}
	if ($flag !~ /^\s*([01])\s*$/)
	{
		$self->{err} = "invalid owner flag - should be 0 or 1";
		return 0;
	}
	$flag = $1;
	if (!$self->exec(q{
		UPDATE access
		SET is_owner=?
		WHERE id=?
		AND username=?
	}, $flag, $id, $username))
	{
		return 0;
	}
	if ($DBI::rows == 0)
	{
		$self->{err} = "user doesn't have access to the credential";
		return 0;
	}
	return 1;
}

# Retrieve a credential from the database, decrypting it
# with a user's private key.
sub getcredential
{
	my ($self, $id, $username, $password) = @_;

	my $user = $self->getuser($username);
	if (!defined($user))
	{
		$self->{err} = "unknown username";
		return undef;
	}

	# Unconditionally call regrant here to help fixup users who
	# have had a password reset.
	$self->regrant($username, $password);

	# Access to a credential by an emergency admin account
	# marks the credential as insecure.
	if ($user->{emergencyadmin})
	{
		if (!$self->exec(q{
			UPDATE credentials
			SET insecure=1
			WHERE ID=?
		}, $id))
		{
			return undef;
		}
	}

	my $encrypted = $self->getrow(q{
		SELECT credentials.encrypted, access.aeskey
		FROM access
		LEFT JOIN credentials USING (ID)
		WHERE username=?
		AND ID=?
	}, $username, $id);
	if (!defined($encrypted))
	{
		$self->{err} = "user or password not found";
		return undef;
	}

	# Decrypt the AES key
	my $key = $self->rsa_decrypt($encrypted->{aeskey}, 
		$user->{privatekey}, $password);
	if (!defined($key))
	{
		$self->{err} = "password incorrect";
		return undef;
	}

	# Return the decrypted credential
	return $self->aes_decrypt($encrypted->{encrypted}, $key);
}

# Retrieve a credential key from the database, decrypting it
# with a user's private key.
sub getkey
{
	my ($self, $id, $username, $password) = @_;

	my $user = $self->getuser($username);
	if (!defined($user))
	{
		$self->{err} = "unknown username";
		return undef;
	}

	# Access to a credential by an emergency admin account
	# marks the credential as insecure.
	if ($user->{emergencyadmin})
	{
		if (!$self->exec(q{
			UPDATE credentials
			SET insecure=1
			WHERE ID=?
		}, $id))
		{
			return undef;
		}
	}

	my $encrypted = $self->getrow(q{
		SELECT aeskey
		FROM access
		WHERE username=?
		AND ID=?
	}, $username, $id);
	if (!defined($encrypted))
	{
		$self->{err} = "user or password not found";
		return undef;
	}

	# Decrypt the AES key
	my $key = $self->rsa_decrypt($encrypted->{aeskey}, 
		$user->{privatekey}, $password);
	if (!defined($key))
	{
		$self->{err} = "password incorrect";
	}
	return $key;
}

# Go through the credentials that are accessible to a user and,
# if any of these should be accessible to a different user who doesn't
# have a key to them (e.g. after a password reset), re-grant them.
# This is not a restricted function as it doesn't affect anyone's
# existing access.
sub regrant
{
	my ($self, $username, $password) = @_;

	if (!$self->begin_work)
	{
		return 0;
	}

	# This horrible query returns all ID,username
	# pairs for which the user has a public key and
	# has been granted access but where the encrypted
	# key in the credentials table is NULL.
	my $q = $self->{db}->prepare(q{
		SELECT access.ID, access.username, users.publickey
		FROM access
		LEFT JOIN users ON (access.username = users.username)
		WHERE access.ID IN (
			SELECT ID
			FROM access
			WHERE username=?
			AND aeskey IS NOT NULL
		)
		AND aeskey IS NULL
		AND access.username <> ?
		AND users.publickey IS NOT NULL
	});
	if (!defined($q) || !$q->execute($username, $username))
	{
		$self->{err} = $DBI::errstr;
		$self->rollback;
		return 0;
	}
	while (defined(my $row = $q->fetchrow_hashref))
	{
		my $key = $self->getkey($row->{ID}, $username, $password);
		if (defined($key))
		{
			my $encrypted = $self->rsa_encrypt($key, $row->{publickey});
			if (!$self->exec(q{
				UPDATE access
				SET aeskey=?
				WHERE ID=?
				AND username=?
			}, $encrypted, $row->{ID}, $row->{username}))
			{
				$self->rollback;
				return 0;
			}
		}
	}
	$self->commit;
	return 1;
}

# Get a user's record from the
# database. You can search by username or by
# ID.
sub getuser
{
	my ($self, $search, $byid) = @_;
	my $ret;
	if (defined($byid) && $byid)
	{
		$ret = $self->getrow(q{
			SELECT *
			FROM users
			WHERE ID=?
		}, $search);
	}
	else
	{
		$ret = $self->getrow(q{
			SELECT *
			FROM users
			WHERE username=?
		}, $search);
	}
	return $ret;
}

# Is $username an owner of $id?
sub is_owner
{
	my ($self, $username, $id) = @_;
	my $row = return defined($self->getrow(q{
		SELECT *
		FROM access
		WHERE username=?
		AND ID=?
		AND is_owner=1
	}, $username, $id)) ? 1 : 0;
}

# Run an SQL query that returns no results. Return
# 1 if all OK, otherwise set $self->{err} and return
# 0.
sub exec
{
	my ($self, $sql, @bind) = @_;
	
	if (!defined($self->{db}->do($sql, undef, @bind)))
	{
		$self->{err} = $DBI::errstr;
		return 0;
	}
	return 1;
}

# Run a query and return the first row of results.
sub getrow
{
	my ($self, $sql, @bind) = @_;
	my $q = $self->{db}->prepare($sql);
	if (!defined($q))
	{
		$self->{err} = $DBI::errstr;
		return undef;
	}
	if (!$q->execute(@bind))
	{
		$self->{err} = $DBI::errstr;
		return undef;
	}
	my $row = $q->fetchrow_hashref;
	$q->finish;
	return $row;
}

# Transaction utilities
sub begin_work
{
	my ($self) = @_;
	if (!$self->{db}->begin_work)
	{
		$self->{err} = $DBI::errstr;
		return 0;
	}
	return 1;
}
sub commit
{
	my ($self) = @_;
	if (!$self->{db}->commit)
	{
		$self->{err} = $DBI::errstr;
		return 0;
	}
	return 1;
}
sub rollback
{
	my ($self) = @_;
	if (!$self->{db}->rollback)
	{
		$self->{err} = $DBI::errstr;
		return 0;
	}
	return 1;
}

# This part would be run only once to generate a public and
# private key for a user. The private key is AES encrypted
# with the user's password.
sub generate_keys
{
	my ($self, $password) = @_;

	my $rsa = Crypt::OpenSSL::RSA->generate_key($self->{pkbits});
	my ($crypted, $key) = 
		$self->aes_encrypt($rsa->get_private_key_string, $password);
	return ($rsa->get_public_key_string(), $crypted);
}

# Given some data and a public key, RSA-encrypt the data and
sub rsa_encrypt
{
	my ($self, $data, $publickey) = @_;

	my $rsa = Crypt::OpenSSL::RSA->new_public_key($publickey);
	return MIME::Base64::encode_base64($rsa->encrypt($data));
}

# Given some encrypted data, a private key and the password to 
# that key, return the RSA-decrupted data.
sub rsa_decrypt
{
	my ($self, $data, $privatekey, $password) = @_;

	return undef unless defined($data);

	# Decrypt the private key.
	$privatekey = $self->aes_decrypt($privatekey, $password);
	if ($privatekey !~ /^-----BEGIN RSA PRIVATE KEY-----/)
	{
		$self->{err} = "AES private key decryption failed to generate a valid key";
		return undef;
	}

	# Decrypt the AES key using the private key.
	my $rsa = Crypt::OpenSSL::RSA->new_private_key($privatekey);
	return $rsa->decrypt(MIME::Base64::decode_base64($data));
}

# AES-encrypt some data, handling padding and including an IV.
sub aes_encrypt
{
	my ($self, $data, $key) = @_;
	
	# If a key is not passed then create one and return it.
	$key = MIME::Base64::encode_base64(Crypt::OpenSSL::Random::random_bytes(32))
		unless defined($key);

	# See comments in aes_decrypt.
	$key =~ /^(.*)$/s;
	my $safekey = $1;

	# Take a hash of the key. This is a quick way to get 32 bytes.
	my $aes = Crypt::Rijndael->new(Digest::SHA::sha256($safekey),
		Crypt::Rijndael::MODE_CBC);

	# Come up with an IV.
	my $iv = Crypt::OpenSSL::Random::random_bytes($self->{ivlen});
	$aes->set_iv($iv);

	# Store the data length at the start of the data so we can
	# recover it later.
	$data = pack('N', length($data)).$data;
	
	# Now pad to a multiple of 16 bytes.
	$data .= Crypt::OpenSSL::Random::random_bytes(16 - length($data) % 16) 
		if (length($data) % 16);

	# Now encrypt
	my $encrypted = $aes->encrypt($data);

	# Return the IV concatenated with the encrypted data along
	# with the key.
	return (MIME::Base64::encode_base64($iv.$encrypted), $key);
}

# AES-decrypt something that was encrypted by aes_encrypt.
sub aes_decrypt
{
	my ($self, $data, $key) = @_;

	# The data is MIME-encoded
	$data = MIME::Base64::decode_base64($data);

	# Take a hash of the key. This is a quick way to get 32 bytes.
	$key = Digest::SHA::sha256($key);

	# The key may be tainted. I don't see a problem with 
	# this myself, so am going untaint it. Crypt::Rijndael 
	# seems to have a bug about taint checking (it erroneously
	# identifies $key as tainted it I assign the untainted
	# value back to it, so I have to create a new variable.
	$key =~ /^(.*)$/s;
	my $safekey = $1;

	my $aes = Crypt::Rijndael->new($safekey, Crypt::Rijndael::MODE_CBC);

	# Retrieve the IV.
	$aes->set_iv(substr($data, 0, $self->{ivlen}));

	# Decrypt the data.
	$data = $aes->decrypt(substr($data, $self->{ivlen}));

	# We now have the packed data length followed by the
	# data followed (possibly) by random padding bytes.
	my $datalen = unpack('N', $data);

	# Little check - if the key was wrong we don't want
	# to try to do an infinite substr!
	if ($datalen < length($data))
	{
		$data = substr($data, 4, $datalen);
	}

	return $data;
}

1;
