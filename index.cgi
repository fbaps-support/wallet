#!/usr/bin/perl

use WebApp;
use lib "/var/www/apps/wallet/lib";
use Wallet;
use HTML::Entities;
use strict;

my $default_expiry = 52;

use CGI;
use CGI::Session;
use Template;

my $db = WebApp::home."/db/wallet.sqlite";

my $cgi = new CGI;
CGI::Session->name("WALLETSID");
my $session = new CGI::Session($cgi);

# Get our Wallet object.
my $wallet = new Wallet($db);
&error("Error opening wallet: $wallet") unless (ref($wallet));

# Ensure validation...
&error("No REMOTE_USER supplied - authentication failed")
	unless (defined($cgi->remote_user));

my $loggedin = $wallet->getuser($cgi->remote_user);
if (!defined($loggedin))
{
	&error("Failed to create user: ".$wallet->err)
		unless ($wallet->createuser($cgi->remote_user) &&
			defined($loggedin = $wallet->getuser($cgi->remote_user)));
}

my $app;
if (!defined($loggedin->{publickey}))
{
	$app = new WebApp(
		cgi => $cgi,
		session => $session,
		state_name => "passwd",
		start_node => "top",
		state_tracker_name => "trackstate",
		display => \&display,
		nodes => {
			top => {
				handlers => [ sub { return "setpassword"; } ],
				next => [ "setpassword" ]
			},
			setpassword => {
				collectors => [ \&header_collector, \&setpassword_collector ],
				handlers => [ \&setpassword_handler ],
				template => "setpassword.tpl",
				next => [ "setpassword" ]
			},
		}
	);
	&error(WebApp::error) unless (defined($app));
	&error($app->error) unless ($app->run);
	exit(0);
}

my @tabs = (
	[ "listcredentials"		=> "List credentials",	1 ],
	[ "createcred"			=> "Create credential", 1 ],
	[ "misc"			=> "Misc stuff", 1 ],
	[ "bulkassign_choose_users"	=> "Bulk assign", 
				scalar(@{$wallet->hasaccess($loggedin->{username}, 1)} > 1) ],
	[ "manageusers"			=> "Manage users", $loggedin->{useradmin} ],
);

my @toptab = ();
map { push(@toptab, $_->[0]) } @tabs;
$app = new WebApp(
	cgi => $cgi,
	session => $session,
	state_name => "wallet",
	start_node => "top",
	state_tracker_name => "trackstate",
	display => \&display,

	nodes => {
		top => {
			handlers => [ sub { return "listcredentials"; } ],
			next => [ "listcredentials" ]
		},
		listcredentials => {
			collectors => [ \&header_collector, \&listcredentials_collector ],
			handlers => [ \&header_handler, \&listcredentials_handler ],
			template => "credentialsform.tpl",
			next => [ @toptab, "listcredentials", "viewcred" ]
		},
		viewcred => {
			collectors => [ \&header_collector, \&viewcred_collector ],
			handlers => [ \&header_handler, \&viewcred_handler ],
			template => "viewcredentialsform.tpl",
			next => [ @toptab, "retrievecred", "editcred", "deletecred", "viewcred" ]
		},
		retrievecred => {
			collectors => [ \&header_collector, \&retrievecred_collector ],
			handlers => [ \&header_handler, \&retrievecred_handler ],
			template => "retrievecredentials.tpl",
			next => [ @toptab, ]
		},
		editcred => {
			collectors => [ \&header_collector, \&editcred_collector ],
			handlers => [ \&header_handler, \&savecredential ],
			template => "editcredentialsform.tpl",
			next => [ @toptab ],
		},
		deletecred => {
			collectors => [ \&header_collector, \&deletecred_collector ],
			handlers => [ \&header_handler, \&deletecred_handler ],
			template => "deletecredentialsform.tpl",
			next => [ @toptab ]
		},
		createcred => {
			collectors => [ \&header_collector, \&createcred_collector ],
			handlers => [ \&header_handler, \&savecredential ],
			template => "editcredentialsform.tpl",
			next => [ @toptab, ],
		},
		misc => {
			collectors => [ \&header_collector, \&misc_collector ],
			handlers => [ \&header_handler, \&misc_handler ],
			template => "miscform.tpl",
			next => [ @toptab, ],
		},
		bulkassign_choose_users => {
			collectors => [ \&header_collector, \&bulkassign_choose_users_collector ],
			handlers => [ \&header_handler, \&bulkassign_choose_users_handler ],
			template => "bulkform.tpl",
			next => [ @toptab, "bulkassign_edit_creds" ]
		},
		bulkassign_edit_creds => {
			collectors => [ \&header_collector, \&bulkassign_edit_creds_collector ],
			handlers => [ \&header_handler, \&bulkassign_edit_creds_handler ],
			template => "bulkmodify.tpl",
			next => [ @toptab ]
			
		},
		manageusers => {
			collectors => [ \&header_collector, \&manageusers_collector ],
			handlers => [ \&header_handler, \&manageusers_handler ],
			template => "userform.tpl",
			next => [ @toptab, "deleteuser" ]
		},
		deleteuser => {
			collectors => [ \&header_collector, \&deleteuser_collector ],
			handlers => [ \&header_handler, \&deleteuser_handler ],
			template => "deleteuserform.tpl",
			next => [ @toptab ]
		}
	}
);

&error(WebApp::error) unless (defined($app));
&error($app->error) unless ($app->run);

sub header_collector
{
	my ($node, $appstate, $R) = @_;
	my $hash = {
		node => $node
	};

	if (defined($appstate->{error}))
	{
		$hash->{error} = ref($appstate->{error}) eq "ARRAY" ? $appstate->{error} : [ $appstate->{error} ];
		delete $appstate->{error};
	}
	if (defined($appstate->{message}))
	{
		$hash->{message} = ref($appstate->{message}) eq "ARRAY" ? $appstate->{message} : [ $appstate->{message} ];
		delete $appstate->{message};
	}
	return $hash;
}
sub header_handler
{
	my ($node, $appstate, $R) = @_;
	if (defined($R->{gotonode}))
	{
		%{$appstate} = ();
		return $R->{gotonode};
	}
	return undef;
}

sub listcredentials_collector
{
	my ($node, $appstate, $R) = @_;
	my $access;

	my $listsettings = $session->param("listsettings");

	&settab($node);
	if (defined($listsettings->{onlymine}))
	{
		$access = $wallet->hasaccess($loggedin->{username}, 1);
	}
	else
	{
		$access = $wallet->hasaccess($loggedin->{username}, 0);
	}
	my %taglist = ();
	my @list = ();
	foreach my $entry (@{$access})
	{
		my $found = 0;
		if (!defined($listsettings->{tag}) || ($listsettings->{tag} eq ""))
		{
			$found = 1;
		}
		foreach my $tag (@{$entry->{tags}})
		{
			$taglist{$tag} = 1;
			if (!defined($listsettings->{tag}) || ($listsettings->{tag} eq "") || ($listsettings->{tag} eq $tag))
			{
				$found = 1;
			}
		}
		if ($found)
		{
			if (($entry->{expiry_weeks} > 0) && ($entry->{last_changed}+$entry->{expiry_weeks}*86400*7 < time))
			{
				$entry->{expired} = 1;
			}
			push(@list, $entry) 
		}
	}
	return {
		settings	=> $listsettings,
		alltags		=> [ sort {$a cmp $b} keys(%taglist) ],
		credentials	=> \@list,
	};
}

sub listcredentials_handler
{
	my ($node, $appstate, $R) = @_;

	foreach my $k (keys(%{$R}))
	{
		if ($k =~ /^view(\d+)$/)
		{
			my $id = $1;
			if (defined($wallet->credentialdetails($id)))
			{
				$appstate->{ID} = $1;
				return "viewcred";
			}
			else
			{
				$appstate->{error} = "This credential does not exist";
				return "listcredentials";
			}
		}
	}

	if (defined($R->{filter}))
	{
		$session->param("listsettings" => {
			onlymine => $R->{onlymine},
			tag => $R->{tag}
		});
		$session->flush();
	}
	return "listcredentials";
}

sub viewcred_collector
{
	my ($node, $appstate, $R) = @_;


	&settab($node);
	my $fulldetails = &fulldetails($appstate->{ID});

	my $error = defined($fulldetails) ? undef : "credential not found";

	my $hash = {
		details => $fulldetails,
		is_owner => $wallet->is_owner($loggedin->{username}, $appstate->{ID})
	};
	$hash->{error} = $error if defined($error);

	return $hash;
}

sub viewcred_handler
{
	my ($node, $appstate, $R) = @_;
	my $credentials = $wallet->getcredential($appstate->{ID}, $loggedin->{username}, $R->{password});
	if (!defined($credentials))
	{
		$appstate->{error} = "Password incorrect or missing";
		return "viewcred";
	}

	if (defined($R->{retrieve}))
	{
		return "retrievecred";
	}
	elsif (defined($R->{edit}))
	{
		return "editcred";
	}
	elsif (defined($R->{delete}))
	{
		return "deletecred";
	}
	return "badrequest";
}

sub retrievecred_collector
{
	my ($node, $appstate, $R) = @_;

	my $credentials = $wallet->getcredential($appstate->{ID}, $loggedin->{username}, $R->{password});
	if (!defined($credentials))
	{
		return {
			error => "Credential not found - should never happen"
		};
	}
	%{$appstate} = ();

	return {
		credentials => $credentials
	};
}
sub retrievecred_handler
{
	return "listcredentials";
}

sub editcred_collector
{
	my ($node, $appstate, $R) = @_;

	if (!$wallet->is_owner($loggedin->{username}, $appstate->{ID}))
	{
		return {
			error => "You are not an owner of this credential - should never happen"
		};
	}

	my $fulldetails = &fulldetails($appstate->{ID});
	if (!defined($fulldetails))
	{
		return {
			error => "Credential not found"
		};
	}

	$fulldetails->{credentials} = $wallet->getcredential($appstate->{ID}, $loggedin->{username}, $R->{password});
	if (!defined($fulldetails->{credentials}))
	{
		return {
			error => "Password incorrect - should never happen"
		};
	}

	my %map = ();
	for (my $i=0; $i<@{$fulldetails->{userlist}}; $i++)
	{
		$map{$fulldetails->{userlist}->[$i]->{username}} = $i;
	}

	# Get a list of passwords I own, and a list of
	# who has access to each.
	my $access = $wallet->hasaccess($loggedin->{username}, 1);
	my $othercreds = [];
	foreach my $ent (@{$access})
	{
		my $details = $wallet->credentialdetails($ent->{ID});
		$details->{description} =~ s/\\/\\\\/g;
		$details->{description} =~ s/"/\\"/g;
		my @info = ( $details->{description} );
		foreach my $u (@{$details->{users}})
		{
			if (defined($map{$u->{username}}))
			{
				push(@info, $map{$u->{username}});
			}
		}
		push(@{$othercreds}, \@info);
	}

	return {
		details => $fulldetails,
		othercreds => $othercreds
	};
}

sub createcred_collector
{
	my ($node, $appstate, $R) = @_;

	&settab($node);
	my $userlist = [];
	my %map = ();
	foreach my $user (@{$wallet->userlist})
	{
		push(@{$userlist}, {
			ID => $user->{ID},
			username => $user->{username},
			owner => $user->{username} eq $loggedin->{username} ? 1 : 0,
			user => $user->{username} eq $loggedin->{username} ? 1 : 0,
		});
		$map{$user->{username}} = @{$userlist}-1;
	}

	# Get a list of passwords I own, and a list of
	# who has access to each.
	my $access = $wallet->hasaccess($loggedin->{username}, 1);
	my $othercreds = [];
	foreach my $ent (@{$access})
	{
		my $details = $wallet->credentialdetails($ent->{ID});
		$details->{description} =~ s/\\/\\\\/g;
		$details->{description} =~ s/"/\\"/g;
		my @info = ( $details->{description} );
		foreach my $u (@{$details->{users}})
		{
			if (defined($map{$u->{username}}))
			{
				push(@info, $map{$u->{username}});
			}
		}
		push(@{$othercreds}, \@info);
	}

	return {
		details => { 
			description => "",
			tags => [],
			expiry_weeks => $default_expiry,
			credentials => "Username: \nPassword: ",
			userlist => $userlist,
		},
		othercreds => $othercreds,
	};
}

sub savecredential
{
	my ($node, $appstate, $R) = @_;

	if ($node eq "createcred")
	{
		$appstate->{ID} = $wallet->createcredential($R->{description}, $R->{expiry},
			$R->{credentials}, $loggedin->{username});
		if (!$appstate->{ID})
		{
			$appstate->{error} = "Failed to create credential: ".$wallet->err;
			return $node;
		}
	}

	if (!$wallet->is_owner($loggedin->{username}, $appstate->{ID}))
	{
		$appstate->{error} = "You are not an owner of this credential";
		return $node;
	}

	my $fulldetails = &fulldetails($appstate->{ID});
	if (!defined($fulldetails))
	{
		$appstate->{error} = "Credential not found - should never happen";
		return "listcredentials";
	}

	$fulldetails->{credentials} = $wallet->getcredential($appstate->{ID}, $loggedin->{username}, $R->{password});
	if (!defined($fulldetails->{credentials}))
	{
		$appstate->{error} = "Password incorrect";
		return $node;
	}

	# Description and expiry details.
	if ($R->{description} ne $fulldetails->{description} || $R->{expiry_weeks} != $fulldetails->{expiry_weeks})
	{
		if (!$wallet->changecredentialproperties($appstate->{ID}, 
			$loggedin->{username}, 0+$R->{expiry_weeks},
			$R->{description}))
		{
			$appstate->{error} = "Failed to save new details: ".$wallet->err;
			return $node;
		}
	}

	# Tags.
	my @tags = split(/\s*,\s*/, $R->{tags});
	if (!$wallet->changecredentialtags($appstate->{ID}, $loggedin->{username}, @tags))
	{
		$appstate->{error} = "Failed to save new tags: ".$wallet->err;
		return $node;
	}

	my @errors = ();
	my %newusers = ();
	foreach my $k (keys(%{$R}))
	{
		if ($k =~ /^user(\d+)$/)
		{
			$newusers{$1} = 1;
		}
	}
	foreach my $user (@{$fulldetails->{userlist}})
	{
		if (defined($newusers{$user->{ID}}) && !$user->{user})
		{
			unless($wallet->grantcredential($appstate->{ID}, $loggedin->{username}, 
				$R->{password}, $user->{username}))
			{
				push(@errors, "Failed to grant access to $user->{username}: ".$wallet->err);
			}
		}
		elsif (!defined($newusers{$user->{ID}}) && $user->{user})
		{
			if ($user->{owner})
			{
				push(@errors, "Can't remove access from $user->{username} - remove ownership first");
			}
			else
			{
				unless($wallet->revokecredential($appstate->{ID}, $loggedin->{username}, 
					$user->{username}))
				{
					push(@errors, "Failed to revoke from $user->{username}: ".$wallet->err);
				}
			}
		}
	}

	if ($R->{credentials} ne $fulldetails->{credentials})
	{
		if (!$wallet->changecredential($appstate->{ID}, $loggedin->{username}, $R->{credentials}))
		{
			push(@errors, "Failed to change credential: ".$wallet->err);
		}
	}

	# Modify ownership. This is the last thing that must be done,
	# just unless the person logged in is removing themselves.
	my %newowners = ();
	foreach my $k (keys(%{$R}))
	{
		if ($k =~ /^owner(\d+)$/)
		{
			$newowners{$1} = 1;
		}
	}

	if (keys(%newowners) == 0)
	{
		push(@errors, "You cannot remove all owners from a credential");
	}
	else
	{
		# Have to make sure that the currently logged in use is the last one
		# we look at.
		my @allusers = @{$fulldetails->{userlist}};
		@allusers = (
			grep($_->{username} ne $loggedin->{username}, @allusers),
			grep($_->{username} eq $loggedin->{username}, @allusers)
		);
		foreach my $user (@allusers)
		{
			if (defined($newowners{$user->{ID}}) && !$user->{owner})
			{
				unless ($wallet->setownerflag($appstate->{ID}, $loggedin->{username}, 
					$user->{username}, 1))
				{
					push(@errors, "Failed to grant ownership to $user->{username}: ".$wallet->err);
				}
			}
			elsif (!defined($newowners{$user->{ID}}) && $user->{owner})
			{
				unless ($wallet->setownerflag($appstate->{ID}, $loggedin->{username}, 
					$user->{username}, 0))
				{
					push(@errors, "Failed to revoke ownership from $user->{username}: ".$wallet->err);
				}
			}
		}
	}

	if (@errors > 0)
	{
		$appstate->{error} = \@errors;
	}
	
	return "listcredentials";
}

sub deletecred_collector
{
	my ($node, $appstate, $R) = @_;

	if (!$wallet->is_owner($loggedin->{username}, $appstate->{ID}))
	{
		return {
			error => "You are not an owner of this credential - should never happen"
		};
	}

	my $details = $wallet->credentialdetails($appstate->{ID});
	if (!defined($details))
	{
		return {
			error => "Credential not found - should never happen"
		};
	}

	return {
		details => $details
	};
}

sub deletecred_handler
{
	my ($node, $appstate, $R) = @_;

	if ($wallet->deletecredential($appstate->{ID}, $loggedin->{username}))
	{
		$appstate->{message} = "Credential deleted";
	}
	else
	{
		$appstate->{error} = "Failed to delete credential: ".$wallet->err;
	}
	return "listcredentials";
}

sub misc_collector
{
	my ($node, $appstate, $R) = @_;
	&settab($node);
}

sub misc_handler
{
	my ($node, $appstate, $R) = @_;

	my $ret = &passwdchecks($R->{password1}, $R->{password2});
	if (defined($ret))
	{
		$appstate->{error} = $ret;
		return "misc";
	}

	if ($wallet->setuserpassword($loggedin->{username}, $R->{password1}, $R->{oldpassword}))
	{
		$appstate->{error} = "Failed to change password: ".$wallet->err;
		return "misc";
	}

	$appstate->{message} = "Password changed";
	return "listcredentials";
}

sub bulkassign_choose_users_collector
{
	my ($node, $appstate, $R) = @_;

	&settab($node);

	my @who = ();
	foreach my $user (@{$wallet->userlist})
	{
		# No point in allowing bulk management of yourself,
		# because you can only manage your own lists anyway and
		# you have to have access to those.
		next if ($user->{username} eq $loggedin->{username});
		push(@who, [ $user->{username}, $user->{ID} ]);
	}
	return {
		userlist => \@who
	};
}
sub bulkassign_choose_users_handler
{
	my ($node, $appstate, $R) = @_;

	my %who = ();
	while (my ($k) = each(%{$R}))
	{
		if ($k =~ /^user(\d+)$/)
		{
			$who{$1} = 1;
		}
	}
	my ($access, $users) = &bulkaccess(\%who);
	my @access = sort {$a->{description} cmp $b->{description}} 
		values(%{$access});

	%{$appstate} = (
		who => \%who,
		userlist => $users,
		access => \@access
	);
	return "bulkassign_edit_creds";
}
sub bulkassign_edit_creds_collector
{
	my ($node, $appstate, $R) = @_;

	return $appstate;
}
sub bulkassign_edit_creds_handler
{
	my ($node, $appstate, $R) = @_;

	my ($currentaccess, $users) = &bulkaccess($appstate->{who});

	my %idmap = ();
	foreach my $user (@{$wallet->userlist})
	{
		$idmap{$user->{ID}} = $user->{username};
	}

	my $newaccess = {};
	while (my ($k) = each(%{$R}))
	{
		if ($k =~ /^access\.(\d+)\.(\d+)$/)
		{
			my ($user, $cred) = ($1, $2);
			$newaccess->{$cred}->{$user} = "GRANT";
		}
	}

	# Take the difference and work out what's needed.
	while (my ($cred, $access) = each(%{$currentaccess}))
	{
		while (my ($username, $info) = each(%{$access->{access}}))
		{
			# Don't do anything in the case where the
			# person is currently an owner.
			next if ($info->[1]);
			if (defined($newaccess->{$cred}->{$info->[0]}))
			{
				delete $newaccess->{$cred}->{$info->[0]};
			}
			else
			{
				$newaccess->{$cred}->{$info->[0]} = "REVOKE";
			}
		}
	}

	# Now do the changes.
	my @errors = ();
	my @messages = ();
	while (my ($cred, $actions) = each(%{$newaccess}))
	{
		while (my ($uid, $action) = each(%{$actions}))
		{
			my $username = $idmap{$uid};
			next unless defined($username);
			if ($action eq "REVOKE")
			{
				if ($wallet->revokecredential($cred,
					$loggedin->{username}, $username))
				{
					push(@messages, "Revoked access for $username to $currentaccess->{$cred}->{description}");
				}
				else
				{
					push(@errors, "Failed to revoke access for $username to $currentaccess->{$cred}->{description}: ".$wallet->err);
				}
			}
			else
			{
				if ($wallet->grantcredential($cred,
					$loggedin->{username}, 
					$R->{password}, $username))
				{
					push(@messages, "Granted access for $username to $currentaccess->{$cred}->{description}");
				}
				else
				{
					push(@errors, "Failed to grant access for $username to $currentaccess->{$cred}->{description}: ".$wallet->err);
				}
			}
		}
	}
	if (@errors > 0)
	{
		$appstate->{error} = \@errors;
	}
	if (@messages > 0)
	{
		$appstate->{message} = \@messages;
	}
	else
	{
		$appstate->{message} = [ "No changes made" ];
	}
	if (@errors > 0)
	{
		return $node;
	}
	return "listcredentials";
}

sub manageusers_collector
{
	my ($node, $appstate, $R) = @_;

	&settab($node);
	unless ($loggedin->{useradmin})
	{
		return {
			error => "You are not a user-administrator"
		};
	}

	return {
		userlist => $wallet->userlist
	};
}
sub manageusers_handler
{
	my ($node, $appstate, $R) = @_;

	unless ($loggedin->{useradmin})
	{
		$appstate->{error} = "You are not a user-administrator";
		return "listcredentials";
	}

	my $action = undef;
	my $user = undef;
	foreach my $k (keys(%{$R}))
	{
		if ($k =~ /^(uatoggle|eatoggle|deluser|reset)(\d+)$/)
		{
			my ($a, $u) = ($1, $2);
			$user = $wallet->getuser($u, 1);
			if (defined($user))
			{
				$action = $1;
				last;
			}
		}
	}
	if (!defined($action))
	{
		$appstate->{error} = "Bad form submission";
		return "listcredentials";
	}

	if ($action eq "uatoggle")
	{
		if ($wallet->modifyuser($user->{username}, $loggedin->{username}, $user->{useradmin} ? 0 : 1, $user->{emergencyadmin}))
		{
			$appstate->{message} = "$user->{username} user-admin status modified";
		}
		else
		{
			$appstate->{error} = "Failed to modify user: ".$wallet->err;
		}
		return $node;
	}
	elsif ($action eq "eatoggle")
	{
		if ($wallet->modifyuser($user->{username}, $loggedin->{username}, $user->{useradmin}, $user->{emergencyadmin} ? 0 : 1))
		{
			$appstate->{message} = "$user->{username} emergency-admin status modified";
		}
		else
		{
			$appstate->{error} = "Failed to modify user: ".$wallet->err;
		}
		return $node;
	}
	elsif ($action eq "reset")
	{
		if ($wallet->resetuserpassword($user->{username}, $loggedin->{username}))
		{
			$appstate->{message} = "$user->{username} password reset";
		}
		else
		{
			$appstate->{error} = "Failed to modify user: ".$wallet->err;
		}
		return $node;
	}
	elsif ($action eq "deluser")
	{
		my $owned = $wallet->hasaccess($user->{username}, 1);
		if (@{$owned} != 0)
		{
			$appstate->{error} = "Can't delete a user who is the owner of a credential";
			return $node;
		}
		else
		{
			%{$appstate} = (
				user => $user
			);
			return "deleteuser";
		}
	}
	return $node;
}

sub deleteuser_collector
{
	my ($node, $appstate, $R) = @_;
	return $appstate;
}
sub deleteuser_handler
{
	my ($node, $appstate, $R) = @_;

	unless ($loggedin->{useradmin})
	{
		$appstate->{error} = "You are not a user-administrator";
		return "listcredentials";
	}

	if ($wallet->deleteuser($appstate->{user}->{username}, $loggedin->{username}))
	{
		$appstate->{message} = "Deleted $appstate->{user}->{username}";
	}
	else
	{
		$appstate->{error} = "Failed to delete user: ".$wallet->err;
	}

	return "manageusers";
}

sub make_links_and_escape
{
		my $in = shift;
		my $out = "";

		my $idnum = 0;
		foreach my $line (split(/\r*\n/, $in))
		{
			my $totp = "";
			my $extra = "";
			if ($line =~ /^(\s*([a-z0-9\s]+)\s*:\s*)(.+)(\s*)$/i)
			{
				$idnum++;
				$extra = sprintf("<input type=\"text\" style=\"position: absolute; left: -9999px;\" id=\"copy%02d\" value=\"%s\"><a href=\"#\" onClick=\"copy('copy%02d')\"><em style=\"margin-right: 4ex\">Copy</em></a>",
					$idnum, HTML::Entities::encode_entities($3), $idnum);

				if (substr($2, -4) eq "TOTP")
				{
					my $key = $3;
					if ($key =~ /^[A-Z2-7\s]+$/i)
					{
						$idnum++;
						$totp = sprintf("<input type=\"text\" style=\"position: absolute; left: -9999px;\" id=\"copy%02d\" value=\"------\"><a href=\"#\" onClick=\"copy('copy%02d')\"><em style=\"margin-right: 4ex\">Copy</em></a>\n",
							$idnum, $idnum);
						$totp .= sprintf("<span style=\"font-family: courier\" id='totp%02d'>OTP Code: ------</span><br><script>updateOTP('%s', '%02d');</script>", $idnum, $key, $idnum);
					};
				}
			}

			if ($line =~ /^(.*?)(https?:\/\/\S+)(.*)$/)
			{
				$line = HTML::Entities::encode_entities($1);
				$line .= "<a href=\"$2\">".$2."</a>";
				$line .= HTML::Entities::encode_entities($3);
			}
			else
			{
				$line = HTML::Entities::encode_entities($line);
			}
			$out .= $extra."\n"."<span style=\"font-family: courier\">$line</span><br>\n";
			$out .= $totp if ($totp ne "");
		}
		return $out;
}

sub display
{
	my ($file, $vars) = @_;
	my $t = Template->new(INCLUDE_PATH => WebApp::home."/templates");
	$t->context()->define_filter("make_links_and_escape", \&make_links_and_escape);

	# Output session header.
	print $session->header(-type => "text/html");

	$vars->{tabs} = \@tabs;
	$vars->{currenttab} = $session->param("currenttab");
	if (!$t->process($file, $vars))
	{
		&warn("Failed to process template $file: ".$t->error());
		exit(1);
	}
}

sub passwdchecks
{
	my ($pass1, $pass2) = @_;

	if ($pass1 ne $pass2)
	{
		return "The entered passwords did not match";
	}

	# Check length.
	if (length($pass1) < 8)
	{
		return "The password is too short";
	}

	# Now count how many distinct letters/digits/
	my %chars = ();
	my $gotletters = 0;
	my $gotdigits = 0;
	my $gotother = 0;
	foreach my $char (split('', $pass1))
	{
		if ($char =~ /[A-Za-z]/)
		{
			$gotletters = 1;
		}
		elsif ($char =~ /[0-9]/)
		{
			$gotdigits = 1;
		}
		else
		{
			$gotother = 1;
		}
		$chars{$char} = 1;
	}

	if (keys(%chars) < 5)
	{
		return "The password has too few distinct characters";
	}

	if ($gotletters + $gotdigits + $gotother == 1)
	{
		return "The password contains too few character types (letters/digits/other)";
	}

	return undef;
}

sub fulldetails
{
	my $id = shift;
	my $details = $wallet->credentialdetails($id);

	if (!defined($details))
	{
		return undef;
	}

	my %perms = ();
	foreach my $user (@{$details->{owners}})
	{
		$perms{$user->{ID}}->{owner} = 1;
	}
	foreach my $user (@{$details->{users}})
	{
		$perms{$user->{ID}}->{user} = 1;
	}
	my $userlist = [];
	foreach my $user (@{$wallet->userlist})
	{
		push(@{$userlist}, {
			ID => $user->{ID},
			username => $user->{username},
			owner => defined($perms{$user->{ID}}->{owner}),
			user => defined($perms{$user->{ID}}->{user})
		});
	}
	$details->{weeks} = int((time - $details->{last_changed})/(86400*7));
	my @t = localtime($details->{last_changed});
	$details->{last_changed} = sprintf("%04d-%02d-%02d", $t[5]+1900, $t[4]+1, $t[3]);
	$details->{userlist} = $userlist;

	return $details;
}

sub setpassword_collector
{
	my ($node, $appstate, $R) = @_;
	$appstate->{hidebar} = 1;
	return $appstate;
}
sub setpassword_handler
{
	my ($node, $appstate, $R) = @_;

	# They can't use this page if they've already got a key.
	if (defined($loggedin->{publickey}))
	{
		$appstate->{error} =  "You already have a password set - should never happen";
		return $node;
	}

	my $err = &passwdchecks($R->{password1}, $R->{password2});
	if (defined($err))
	{
		$appstate->{error} = $err;
		return $node;
	}

	if (!$wallet->setuserpassword($loggedin->{username}, $R->{password1}))
	{
		$appstate->{error} = "Setting a password failed: ".$wallet->err;
		return $node;
	}
	$app->load;
}

sub bulkaccess
{
	my $who = shift;
	my $mine = $wallet->hasaccess($loggedin->{username}, 1);

	my %access = ();
	foreach my $cred (@{$mine})
	{
		$access{$cred->{ID}} = {
			ID => $cred->{ID},
			description => $cred->{description},
			access => {}
		};
	}
	my @all = ();
	foreach my $user (@{$wallet->userlist})
	{
		if (defined($who->{$user->{ID}}))
		{
			push(@all, [ $user->{username}, $user->{ID} ]);
			foreach my $cred (@{$wallet->hasaccess($user->{username}, 0)})
			{
				$access{$cred->{ID}}->{access}->{$user->{username}} = [ $user->{ID}, $cred->{is_owner} ]
					if (defined($access{$cred->{ID}}));
			}
		}
	}
	return (\%access, \@all);
}

sub settab
{
	my $tab = shift;
	$session->param("currenttab" => $tab);
}

sub error
{
	&display("header.tpl", {
		hidebar => 1,
		error => \@_,
	});
	&display("footer.tpl");
	exit(0);
}

use Data::Dumper;
sub debug
{
	&warn("<pre>".Dumper($_[0])."</pre>");
}
