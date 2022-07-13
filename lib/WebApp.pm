package WebApp;

my $error;

use Cwd ();
use Template;
use POSIX;
use CGI;
use CGI::Session;
use Data::Dumper;
use IO::Compress::Gzip;

my %valid_new_args = (
	session			=> 1,
	cookie_path		=> 1, 
	secure_cookie		=> 1,
	template_cache_dir	=> 1,
	compress		=> 1,
	cgi			=> 1,
	display			=> 1, 
	templates		=> 1,
	start_node		=> 1,
	state_name		=> 1,
	state_tracker_name	=> 1,
	debugvar		=> 1,
	function_check		=> 1,
	nodes			=> 1,
);


sub new
{
	my $class = shift;

	# Don't copy across arguments we don't know about. 
	# If an inheriting class wants to copy other stuff in, it's up to that class.
	my $self = {};

	# Check the args we're being called with. There must
	# be an even number, and keys must not be duplicates.
	if (scalar(@_) % 2)
	{
		return $self->_error("new was called with an odd number of arguments");
	}
	for (my $i=0; $i<@_; $i+=2)
	{
		my ($k, $v) = @_[$i..$i+1];
		if (defined($valid_new_args{$k}))
		{
			if (exists($self->{$k}))
			{
				$error = "Duplicate argument '$_[$i]' passed to new()";
				return undef;
			}
			else
			{
				$self->{$k} = $v;
			}
		}
		$self->{$k} = $v;
	}

	bless $self;

	$self->{sentheader} = 0;
	$self->{killed} = 0;
	$self->{session_is_mine} = 0;
	$self->{stash} = {};
	$self->{debugdata} = "";

	# We need to have a CGI object so we can get to its variables
	# and use it to print headers.
	if (!defined($self->{cgi}))
	{
		if (defined($self->{session}))
		{
			$self->{cgi} = $self->{session}->query();
		}
		else
		{
			$self->{cgi} = new CGI;
		}
	}

	if (defined($self->{display}) && defined($self->{templates}))
	{
		return $self->_error("Only one of display and templates can be supplied");
	}
	if (!defined($self->{display}) && !defined($self->{templates}))
	{
		return $self->_error("Either display or templates must be supplied");
	}

	# Canonicalise the templates path.
	if (defined($self->{templates}))
	{
		my @new = ();
		my $home = &home;
		foreach my $dir (split(":", $self->{templates}))
		{
			$dir = Cwd::abs_path("$home/$dir")
				unless ($dir =~ m#^/#);
			push(@new, $dir);
		}
		# Untaint the path.
		map {/^(.*)$/; $_ = $1;} @new;
		$self->{templates} = join(":", @new);
	}

	# If it's a function reference then the function must
	# exist. If it's a class object then it must display a
	# method called display.
	if (defined($self->{display}))
	{
		if (ref($self->{display}) eq "CODE")
		{
			return $self->_error("Display function not provided")
				unless (defined(&{$self->{display}}));
		}
		elsif (!eval { $self->can("display") } )
		{
			return $self->_error("Object passed as display does not provide a display method");
		}
	}

	# If a state name has been supplied then create and manage a session.
	if (defined($self->{state_name}) && !defined($self->{session}))
	{
		# I don't like this, but setting the name after you've created the session
		# object just doesn't seem to work.
		CGI::Session->name($self->{state_name});
		$self->{session} = new CGI::Session($self->{cgi});

		# I need to know that the session was created by me, so that if/when I come to
		# kill the session I know how much to kill.
		$self->{session_is_mine} = 1;

		# Unless otherwise specified, tie down the cookie path
		# as far as possible.
		if (!defined($self->{cookie_path}))
		{
			if (defined($ENV{'SCRIPT_NAME'}))
			{
				$self->{cookie_path} = $ENV{'SCRIPT_NAME'};

				# Trim off the leaf name.
				$self->{cookie_path} =~ s#/[^/]+$##;
			}
			else
			{
				$self->{cookie_path} = "/";
			}
		}

		# Unless otherwise specified, secure the cookie if it's
		# been requested via SSL. But don't let them specify
		# secure_cookie=1 if they're not coming across HTTP in
		# the first place.
		if (!defined($self->{secure_cookie}) || ($self->{secure_cookie} != 0))
		{
			$self->{secure_cookie} = (defined($ENV{"HTTPS"}) && ($ENV{"HTTPS"} eq "on")) ? 1 : 0;
		}
	}
	
	# At this point we can run a minimal system without session
	# data, just providing the "stash" and "display" functionality.
	# Check that none of the other "runnable" options are available.
	if (!defined($self->{start_node}) && !defined($self->{nodes}))
	{
		$self->{runnable} = 0;
		return $self;
	}
	$self->{runnable} = 1;

	return $self->_error("No session state name provided")
		unless defined($self->{state_name});

	return $self->_error("No start node provided")
		unless defined($self->{start_node});
	
	return $self->_error("Start node $self->{start_node} doesn't exist")
		unless defined($self->{nodes}->{$self->{start_node}});

	return $self->_error("The start node must not have a collector specified")
		if defined($self->{nodes}->{$self->{start_node}}->{collectors});

	return $self->_error("The start node must not have a template specified")
		if defined($self->{nodes}->{$self->{start_node}}->{template});

	$self->{nodes}->{$self->{start_node}}->{seen} = 1;
	my $function_check_error = "";
	while (my ($name, $node) = each(%{$self->{nodes}}))
	{
		if (!defined($node->{next}) || (@{$node->{next}} == 0))
		{
			return $self->_error("A handler function list was provided for $name but no \"next\" nodes were declared")
				if (defined($node->{handlers}) && (@{$node->{handlers}} > 0));
		}
		else
		{
			return $self->_error("No handler function list provided for $name")
				unless defined($node->{handlers});
		}

		return $self->_error("No template provided for $name")
			if (($name ne $self->{start_node}) && (!defined($node->{template})));

		# Collector functions are optional.
		$node->{collectors} = [ sub { return {} } ] 
			unless (defined($node->{collectors}));

		# Check function list at instantiation.
		if (defined($self->{function_check}) && $self->{function_check})
		{
			for (my $i=0; $i<@{$node->{collectors}}; $i++)
			{
				$function_check_error .= "Collector function $i for node $name is not present\n"
					unless defined(&{$node->{collectors}->[$i]});
			}
			for (my $i=0; $i<@{$node->{handlers}}; $i++)
			{
				$function_check_error .= "Handler function $i for node $name is not present\n"
					unless defined(&{$node->{handlers}->[$i]});
			}
		}

		my %nexthash = ();
		foreach my $next (@{$node->{next}})
		{
			return $self->_error("Node $name specifies unknown next node $next")
				unless defined($self->{nodes}->{$next});

			return $self->_error("The start node may not specify itself as a next node")
				if (($name eq $self->{start_node}) && ($next eq $self->{start_node}));

			$self->{nodes}->{$next}->{seen} = 1;
			$nexthash{$next} = 1;
		}
		$node->{next} = \%nexthash;
	}

	if ($function_check_error ne "")
	{
		return $self->_error($function_check_error);
	}

	foreach my $node (keys(%{$self->{nodes}}))
	{
		return $self->_error("Node $node never gets visited")
			unless (defined($self->{nodes}->{$node}->{seen}));
	}

	return $self;
}

sub home
{
	# Find where we are...
	my $fn = defined($ENV{'SCRIPT_FILENAME'}) ? $ENV{'SCRIPT_FILENAME'} : $0;
	$fn = $1 if ($fn =~ /^(.*)$/);

	my $home = Cwd::abs_path($fn);
	$home = $1 if ($home =~ /^(.*)$/);
	$home =~ s#/[^/]*$##;

	return $home;
}

sub use
{
	my ($module) = @_;
	unshift(@INC, &home."/lib/");
	eval "require $module";
	shift(@INC);
}

sub session
{
	my ($self) = @_;

	return exists($self->{session}) ? $self->{session} : undef;
}

sub cgi
{
	my ($self) = @_;
	return $self->{cgi};
}

# Return a header, taking into account any session we may
# have set up.
sub header
{
	my ($self, %args) = @_;

	return "" if ($self->{sentheader});
	$self->{sentheader} = 1;

	return $self->{cgi}->header($self->_headerargs(%args));
}

# Generate args for CGI::redirect and CGI::header
sub _headerargs
{
	my ($self, %args) = @_;

	if (keys(%args) == 0)
	{
		%args = (
			-type => "text/html",
			-expires => "Sat, 26 Jul 1997 05:00:00 GMT",
			-Last_Modified => POSIX::strftime('%a, %d %b %Y %H:%M:%S GMT', gmtime),
			-Pragma => 'no-cache',
			-Cache_Control => "private, no-cache, no-store, must-revalidate, max-age=0, pre-check=0, post-check=0"
		);
	}

	$args{"-type"} = "text/html" unless (defined($args{"-type"}));

	if (defined($self->{session}))
	{
		my %cookie = (
			-name => $self->{session_is_mine} == 1 ? $self->{state_name} : $self->{session}->name,
			-path => $self->{cookie_path},
			-secure => $self->{secure_cookie},
		);

		if ($self->{killed})
		{
			if ($self->{session_is_mine})
			{
				$cookie{"-value"} = "";
				$cookie{"-expires"} = "-3M";
				$self->{session_is_mine} = 0;
			}
		}
		else
		{
			$cookie{"-value"} = $self->{session}->id;
		}

		my $cookie = CGI::Cookie->new(%cookie);
		if (defined($args{"-cookie"}))
		{
			if (ref($args{"-cookie"}))
			{
				push(@{$args{"-cookie"}}, $cookie);
			}
			else
			{
				$args{"-cookie"} = [ $args{"-cookie"}, $cookie ];
			}
		}
		else
		{
			$args{"-cookie"} = $cookie;
		}
	}
	return %args;
}

sub stash
{
	my ($self, %vars) = @_;
	while (my ($k, $v) = each(%vars))
	{
		$self->{stash}->{$k} = $v;
	}
	return $self->{stash};
}

sub findqueryvars
{
	my ($self, $basename, $maxnum) = @_;
	my %v = $self->{cgi}->Vars;

	my $matches = [];
	while (my ($k) = each(%v))
	{
		if ($k =~ /^$basename(\d+)$/ && ($1 <= $maxnum))
		{
			push(@{$matches}, int($1));
		}
	}
	if (@{$matches} > 0)
	{
		@{$matches} = sort {$a <=> $b} @{$matches};
		return $matches;
	}
	return undef;
}

sub debug
{
	my ($self, $format, @args) = @_;
	if (defined($self->{debugvar}))
	{
		my ($package, $file, $lineno) = caller;
		$file =~ s#^.*/##;

		my $output;
		if (@args > 0)
		{
			$output = sprintf($format, @args);
		}
		elsif (ref($format))
		{
			$Data::Dumper::Sortkeys = 1;
			$output = Data::Dumper::Dumper($format);
		}
		else
		{
			$output = $format;
		}
		foreach my $line (split('\n+', $output))
		{
			my $escaped = $self->{cgi}->escapeHTML($line);
			$escaped =~ s/\s/&nbsp;/g;
			$self->{debugdata} .= "DEBUG $file:$lineno: $escaped<br/>\n";
		}
	}
	return $self->{debugdata};
}

# Used by display and any inherited display to get 
# the stash and debug data into a single hash for passing to
# template toolkit.
sub _templatevars
{
	my ($self, $vars) = @_;
	my %new = ();

	while (my ($k, $v) = each(%{$self->{stash}}))
	{
		$new{$k} = $v;
	}
	while (my ($k, $v) = each(%{$vars}))
	{
		$new{$k} = $v;
	}

	# If a debug variable has been specified then 
	# copy any stored debug data into it.
	if (defined($self->{debugvar}))
	{
		$new{$self->{debugvar}} = $self->{debugdata};
	}

	return \%new;
}

sub display
{
	my ($self, $file, $vars, $output_ref) = @_;
	if (defined($self->{display}))
	{
		if (ref($self->{display}) eq "CODE")
		{
			return &{$self->{display}}($file, $self->_templatevars($vars), $output_ref);
		}
		else
		{
			return $self->{display}->display($file, $self->_templatevars($vars), $output_ref);
		}
	}

	my %args = (INCLUDE_PATH => $self->{templates});
	if (defined($self->{template_cache_dir}))
	{
		$args{'COMPILE_DIR'} = $self->{template_cache_dir};
		$args{'COMPILE_EXT'} = ".tpc";
	}
	my $t = Template->new(%args);
	
	my $err;
	if (!defined($output_ref))
	{
		my $header = $self->header();
		if ($header ne "")
		{
			if (!defined($self->{compress}) || (defined($self->{compress}) && $self->{compress}))
			{
				my $compressions = $self->cgi->http('Accept-Encoding');
				if ($compressions =~ /gzip/i)
				{
					print "Content-Encoding: gzip\n$header";
					$self->{output} = new IO::Compress::Gzip \*STDOUT;
				}
				else
				{
					print $header;
				}
			}
			else
			{
				print $header;
			}
		}
		$ok = $t->process($file, $self->_templatevars($vars), $self->{output});
		$self->{output}->flush(2) if (defined($self->{output}));	# Z_SYNC_FLUSH
	}
	else
	{
		$ok = $t->process($file, $self->_templatevars($vars), $output_ref);
	}
	if (!$ok)
	{
		print "<html><body><b>Error processing template: ".$t->error()."</b></body></html>";
		return $self->_error($t->error());
	}
	return undef;
}

sub panic
{
	shift(@_) if (ref($_[0]));

	my ($message) = @_;
	my $q = new CGI;
	print $q->header(-type => "text/plain");
	print "$message\n";
	exit;
}

sub error { return $error; }

sub run
{
	my ($self) = @_;

	return $self->_error("This object has no defined nodes - not runnable")
		unless ($self->{runnable});

	my $reset = {
		node => $self->{start_node},
		appstate => {},
	};

	my $state = $self->{session}->param($self->{state_name});

	$state = $reset unless (defined($state) && defined($state->{node}));

	# Using $self->{cgi}->Vars directly leaves you having to
	# decode multi-valued items yourself. So I'm going to do it
	# here.
	my %v = $self->{cgi}->Vars;
	my $R = {};
	foreach my $k (keys(%v))
	{
		my @v = $self->{cgi}->multi_param($k);
		if (@v == 1)
		{
			$R->{$k} = $v[0];
		}
		else
		{
			$R->{$k} = [ @v ];
		}
	}

	my $node = $self->{nodes}->{$state->{node}};

	# The start node only has handlers, so can't do tracking.
	my $ok = 1;
	if (($state->{node} ne $self->{start_node}) &&
		defined($self->{state_tracker_name}) && 
		defined($state->{state_tracker}))
	{
		$ok = 0;
		if (defined($R->{$self->{state_tracker_name}}) &&
			$R->{$self->{state_tracker_name}} eq $state->{state_tracker})
		{
			$ok = 1;
		}
	}

	if ($ok)
	{
		my $next = $self->_handle($node, $state, $R);

		return undef unless defined($next);
		return $self->_error("Handler for $state->{node} returned an undeclared next node '$next'")
			unless (defined($node->{next}->{$next}));
		$state->{node} = $next;
	}
	else
	{
		# Tracking failed - back to top node.
		$R = {};
		$state = $reset;
		$self->{session}->param($self->{state_name} => $state);
		$self->{session}->flush;
		return $self->run;
	}

	if ($state->{node} eq $self->{start_node})
	{
		return $self->run;
	}

	$node = $self->{nodes}->{$state->{node}};

	my $hash = {};
	foreach my $collector (@{$node->{collectors}})
	{
		unless (defined(&{$collector}))
		{
			return $self->_error("A collector function for $state->{node} is not present");
		}
		my $subhash = &{$collector}($state->{node}, $state->{appstate}, $R);
		while (my ($k, $v) = each(%{$subhash}))
		{
			$hash->{$k} = $v;
		}
	}

	if (defined($self->{state_tracker_name}))
	{
		my $len = 16;
		my @alphabet = ("a" .. "z", "A" .. "Z", "0" .. "9");
		my $key = "";
		for (my $i=0; $i<$len; $i++)
		{
			$key .= $alphabet[int(rand(scalar(@alphabet)))];
		}
		$hash->{$self->{state_tracker_name}} = $key;
		$state->{state_tracker} = $key;
	}
	$self->{session}->param($self->{state_name} => $state);
	$self->{session}->flush();

	# If the current node has no next nodes then it's an exit point from
	# the application. So kill myself!
	if (scalar keys(%{$node->{next}}) == 0)
	{
		$self->kill;
	}

	$self->display($node->{template}, $hash);
	return 1;
}

# Generate a redirect to a URL. If the URL is not defined, then
# load the current URL with any GET request arguments stripped off.
sub load
{
        my ($self, $url) = @_;

        unless (defined($url))
        {
                $url = $ENV{'REQUEST_URI'};
                $url =~ s/\?.*$//;
        }

	my %args = $self->_headerargs(
		-uri => $url
	);

        print $self->{cgi}->redirect(%args);

        exit(0);
}

# Mark this object as killed. The next call to headers or load will
# generate a header which kills the cookie, and when this object
# goes out of scope the DESTROY function will remove the stored session
# data.
sub kill
{
	my ($self) = @_;

	if (defined($self->{session}))
	{
		if ($self->{session_is_mine})
		{
			# If I own it, I can delete the session completely.
			$self->{session}->delete();
			$self->{session}->flush();
			$self->{session} = undef;
		}
		else
		{
			# If I don't, I should clear out the bit of it that I own.
			$self->{session}->clear($self->{state_name});
			$self->{session}->flush();
		}
	}
	$self->{killed} = 1;
}

# Generate a graphviz "dot" representation of the state machine.
sub graph
{
	my ($self, @dotextras) = @_;

	my $dot = qq/digraph \"WebApp graph for $0\" {\n/;
	$dot .= qq/root=$self->{start_node};\n/;
	$dot .= qq/overlap=scale;\n/;
	foreach my $attr (@dotextras)
	{
		$dot .= $attr.";\n";
	}

	while (my ($node, $config) = each(%{$self->{nodes}}))
	{
		$dot .= sprintf(qq/"%s" [URL="#" tooltip="%s"];\n/, 
			$node, $config->{template});
	}
	while (my ($node, $config) = each(%{$self->{nodes}}))
	{
		while (my $next = each(%{$config->{next}}))
		{
			$dot .= qq/"$node" -> "$next";\n/;
		}
	}
	$dot .= qq/}\n/;

	return $dot;
}

# Output a raw page containing the graph.
sub showgraph
{
	my ($self, $type) = @_;

	my %types = (
		svg => [ "image/svg+xml", "svg" ],
		dot => [ "text/plain", "dot" ],
		png => [ "image/png", "png" ],
	);
	$type = "svg" unless defined($types{$type});

	my $dot = $self->graph(
		qq/size=7/,
		qq/sep=1/,
		qq/nodesep=0.5/,
		qq/concentrate=false/,
		qq/splines=true/,
		qq/ranksep=3/,
	);

	my ($mime, $tflag) = @{$types{$type}};

	printf "Content-Type: $mime\n\n";
	$ENV{'PATH'} = '/bin:/usr/bin';
	open(P, "|dot -Ktwopi -T$tflag") || die "dot not found\n";
	print P $dot;
	close(P);
	exit(0);
}

# Given a node, call entries from the handlers array until one
# returns a defined value. Return that value.
sub _handle
{
	my ($self, $node, $state, $R) = @_;
	my $next;
	foreach my $handler (@{$node->{handlers}})
	{
		unless (defined(&{$handler}))
		{
			return $self->_error("A handler function for $state->{node} is not present");
		}

		$next = &{$handler}($state->{node}, $state->{appstate}, $R);

		last if defined($next);
	}
	if (!defined($next))
	{
		return $self->_error("No handler function for $state->{node} returned a value");
	}
	return $next;
}

sub _error 
{
	$error = $_[1]; 
	return undef; 
}

1;

__END__

=head1 NAME

WebApp - a simple web application framework

=head1 SYNOPSIS

	use WebApp;

	$app = new WebApp(
		...
	);

	$app->run() || $app->panic("Disaster!");

=head1 DESCRIPTION

The WebApp extension module allows the creation of a state machine representing a web 
application. It handles all the internal state management of an application allowing you 
to get on with writing the code that actually does stuff. WebApp can also be used for 
simpler applications, just acting as a helper to display templates.

=head1 SIMPLE APPLICATIONS

Much of the cleverness of WebApp is to do with tracking state, and it's recommended you 
use the state machine (see L<"STATE MACHINE APPLICATIONS">) for all but the
simplest of applications. Nevertheless, sometimes you just want to do something
very simple that doesn't really need any state tracking. WebApp can help you
out here by providing a simple interface to L<Template Toolkit|Template>,
ensuring you're in the right directory and giving access to debugging
functions.

In "simple" mode, here's how you create and use a WebApp object:

	$app = new WebApp(
		templates => "template_dir",
		debugvar => "debugging"
	);

	$app->stash(current_time => scalar localtime);
	
	$app->debug("Running at %d", time);
	
	$app->display("template.tpl", {
		greeting => "Hello world!",
		farewell => "Goodbye cruel world!",
	});
	
In this example, the template toolkit file found in the directory named "template_dir" inside
the application's home directory will be displayed. It will be handed template variables named
current_time, debugging, greeting and farewell.

See L</"ARGUMENTS TO new()"> for details of the values that can be passed to new.

=head1 STATE MACHINE APPLICATIONS

This is where the real power of WebApp lies. The idea is to break down your application into
a set of nodes (pages) and to define the transitions that can occur between these nodes. Each
node has the following properties:

=over

=item template

The name of a L<Template Toolkit|Template> file which is to be displayed when 
the application arrives at this node.

=item next

An array of node names indicating the possible next states which can be arrived
at from this node.

=item collectors

An array of functions which will be run prior to the display of the template.
These functions will be called in turn and should return a hash containing 
S<< key => value >> pairs that should be passed to the template. The hash passed 
to the template will be the result of merging all hashes returned by all collectors.
Typically you'll only need one collector per node, but there are situations
where several are needed (e.g. if you have a dynamically generated button bar
which will be the same on all pages - just define a single collector function
which returns the button list and add it as a collector to all nodes).

The collectors property can be omitted if no data needs to be collected for the
current node.

=item handlers

An array of functions which will be run in response to the next request received 
whilst at this node. This will typically be after a form presented by the node's 
template has been submitted.

These functions are called in turn until one of them returns a defined value 
(i.e. not undef). Handlers are expected to handle the query data and return the
name of a new node to move to. It is an error if no node returns a defined value,
or any node returns a value that's not in the "next" list for this node.

Once a handler has returned the name of the next node, that node's collectors will
be executed and its template will be displayed.

The handlers property can be omitted if no requests are expected in response to this
node. If no handers are listed then no "next" nodes may be identified. When the
application reaches such a node, it is assumed to be an exit point of the
application and any application session / managed cookie will be destroyed
prior to displaying the page.

=back

=head1 ARGUMENTS TO new()

=over

=item B<session> (optional)

This is a L<CGI::Session> object. If you don't pass one in and the application 
needs one, it will be created by the application. In most cases you can just
let WebApp manage it.

=item B<cookie_path> (optional)

This is the path that will be supplied with the Set-Cookie: header for any session 
cookie used. If you don't set it, it will be set to the URI of the directory holding
the application.

In most cases you should let WebApp manage it. It's only if you have several components
to your application, living in disjoint URI paths that you'd wish to change it.

=item B<secure_cookie> (optional)

If this is set it will control whether the cookie is set to secure or not. Even
if you supply it, its value will be overridden to 0 if your application is not
living inside a SSL protected site.

In most cases you should let WebApp manage it. If WebApp is managing it, it will 
set the cookie to be secure if running within a SSL environment.

=item B<cgi> (optional)

This is a L<CGI> object. If you don't pass one in, WebApp will either extract the
one used by any L<CGI::Session> object it has available or will create one for you.

=item B<templates> and B<display> (one or other must be supplied)

B<templates> is the name of a directory in which WebApp can find templates. Given
that WebApp will have changed directory to the application's home, this name can
be a path relative to the application home.

B<display> can be one of two things:

=over

=item A reference to a function 

=item An object supplying a B<display> method 

=back

WebApp will call the function or method with the template filename and a
hash of template variables.

Typically it's more useful to subclass WebApp and override its B<display> method
rather than supplying a function or an object.

=item B<start_node> (mandatory when using the state machine)

You need to nominate the name of a starting node. This node will be visited
when the application has no valid saved state. It does not have any collectors
or a template, but defines a handler list and next node list. The start node can
be used to initialise session state and, possibly, make a decision between
several possible starting points for your application's user interface. For
example, an application may provide a user-level interface and an admin
interface. The start node might wish to start normal users off on one page and
admins on another.

=item B<state_name> (mandatory when using the state machine, optional otherwise)

Since the state machine needs to maintain erm.... state... it needs to use a session. 
If you've passed in a L<CGI::Session> object then the state will be stored in a hash
stored using B<state_name> as its name within the session object. If WebApp has created
a session for you, B<state_name> will also be used as the name of the cookie for this
state. When using WebApp in its simple mode, this is a simple way of getting hold of 
a session to use.

=item B<state_tracker_name> (optional when using the state machine, ignored otherwise)

One terrible problem I find with web applications is that if the user double-submits 
a form, or uses the back button to navigate around the application, we can get very 
confused. B<state_tracker_name> is an attempt to detect this and reset an application
when problems occur. If you set B<state_tracker_name> to the name of a template variable 
then on each call to display you will receive a variable with that name, containing a 
random string of letters. You should then arrange that your application posts this string 
back in a variable with the same name (hidden form field, for example). WebApp
will compare its value with the value stored in the session. If they are not equal then
WebApp knows that an out-of-sequence request has happened. In this case it will clear
all session data and return to the B<start_node>, so resetting the application.

=item B<debugvar> (optional)

If this is set to the name of a template variable then calls to $app->debug() will
store data into this variable and it will be made available to the template. You can
set this while developing or debugging, then unset it to disable all debugging
output. Or you can e.g. make it conditional on requesting IP address so that
the developer gets debugging output on a live system.

=item B<function_check> (optional)

If set to a non-zero value, this will cause WebApp to validate the existence of all
handlers and collectors when it's instantiated. If anything is missing then $app->new()
will return undef and WebApp::error will contain an error message.

If this is omitted or set to zero then WebApp will assumes all is OK and omit this check. 
I recommend always setting function_check to 1 unless the performance hit is demonstrated to 
be unacceptable in production use.

=item B<nodes> (mandatory when using the state machine)

This is the state machine definition. It's a reference to a hash (typically an anonymous 
hash) whose keys are node names and whose values are node definitions. All nodes within
the application must be identified here, along with their handlers, templates and interlinks.

Each node definition is another (anonymous) hash containing:

=over

=item B<template>

The name of the template associated with this node.

=item B<collectors>

An array reference containing function references to the collector functions.

=item B<handlers>

An array reference containing function references to the collector functions.

=item B<next>

An array reference containing the names of all nodes it's possible to reach from this one.

=back

=back 

=head2 Example state machine definition

	my $app = new WebApp(
		state_name => "example",
		start_node => "top",
		state_tracker_name => "trackstate",
		templates => "templates",
		function_check => 1,
		nodes => {
			top => {
				handlers => [ sub { return "main"; } ],
				next => [ "main" ]
			},
			main => {
				collectors => [ \&main_collector ],
				handlers => [ \&main_handler ],
				template => "main.tpl",
				next => [ "main", "add", "delete" ]
			},
			add => {
				collectors => [ \&add_collector ],
				handlers => [ \&add_handler ],
				template => "add.tpl",
				next => [ "add", "main" ]
			},
			delete => {
				collectors => [ \&delete_collector ],
				handlers => [ \&delete_handler ],
				template => "delete.tpl",
				next => [ "add", "main" ]
			}
		}
	);
	WebApp::panic(WebApp::error) unless defined($app);
	$app->run || $app->panic(WebApp::error);

This defines an application whose state will be stored a session. The 
cookie associated with the session will be named "example". The entry point
to the application is identified by via the node named "top". Templates 
will be found in a directory named "templates" and we've asked for a
template variable named "trackstate" to be used to detect client side
state breakage. We've also asked WebApp to check that all functions
referenced in handlers and collectors are indeed present.

The "top" node has a single handler which unconditionally returns "main". It 
identifies a single "next" node named "main". So when you enter the
application you will go via the "top" handler to the "main" state.

The "main" node has a collector named "main_collector", which will return
some data for presentation via the template "main.tpl". This template
presents a form whose results will be passed to "main_handler". Valid next
nodes for "main" are "main", "add" and "delete", and "main_handler" will
return one of these names.

And so on, for add and delete.

=head2 Collector functions

Collector functions should have the following definition:

	sub whatever_collector
	{
		my ($node, $appstate, $R) = @_
		
		....
	
		return {
			key1 => value1,
			key2 => value2,
			...
		}
	}

$node is the name of the current node. This allows for the case that a
collector is being used for multiple nodes and needs to know which one the
application is currently at.

$appstate is a hash which is stored in the session between calls. You can
put whatever persistent state you wish to maintain into this hash.

$R a hash containing the CGI query variables.

The returned hash is merged with any hashes returned by other collectors for
this node, along with any stashed and debug data, then supplied to the
template for display.

=head2 Handler functions

Handler functions should have the following definition:

	sub whatever_handler
	{
		my ($node, $appstate, $R) = @_

		...

		return "next_node";
	}

$node, $appstate and $R are as described above. The handler does whatever's
necessary with the posted data and returns the name of the next node to move
to.

=head2 Progress of execution

When $app->run() is called assuming there's no error indicated by any state
tracker, execution is as follows:

=over

=item Current node's handlers are called in turn until one identifies a new node.

=item New node's collectors are called, collating the template variables.

=item The new node's template is displayed.

=item $app->run() returns (and your CGI probably exits at this point).

=back

Data which is stashed at any point after the creation of the WebApp object
is only available during execution of the CGI. Effectively, you can stash
data for the B<next> display of a template. If you wish for data to be
shared between the collector and the handler of a single node, you need to 
store it in $appstate so it goes into the session data. Remember, the
collector and handler of a node will be run in different instances of your
CGI.

=head1 OBJECT METHODS

=over

=item $app->home() or WebApp::home

This returns the home directory of the application with any symbolic links
resolved. This function doesn't require an object in order to work. You can 
use this to make your script independent of the directory it's installed in
or running from by making sure any files in your application are referred to
relative to WebApp::home.

=item $app->use("Name") or WebApp::use("Name")

This does roughly the same as "use" does, but does it at runtime and temporarily
prepends WebApp::home()."/lib" to the include path. This is needed for scripts
running under a ModPerl::Registry environment. You can't easily do "use lib" in
that context and you can't guarantee what directory you'll be in at the time
the script runs.

=item $app->cgi()

This returns the CGI object that the application is using.

=item $app->session()

This returns the CGI::Session object, if any, that the application is using.

=item $app->header(%args)

This returns a HTTP header as created by CGI::header. It uses %args, augmented
with whichever arguments are needed by the application (principally any session
cookie). If $app->header() is called more than once, the second and subsequent
calls will return an empty string. This is so that $app->display() can be used
multiple times to construct more complicated pages.

=item $app->stash(name => "value", name2 => "value2", ...)

This allows you to stash a (name, variable) pair in this instance of the application. 
The stashed variables will be available to the template displayed by $app->display().
B<N.B.> stashing a value makes it available for just this run of the script. It 
B<does not> get stored into the session.

=item $app->findqueryvars("basename", maxnum)

Quite often, I find myself needing to have a bunch of numbered form fields
(e.g. a bunch of submit buttons), then to pull back the list of them from the
submitted data (e.g. which one was pressed). $app->findqueryvars() does this.
You specify a base name - e.g.  "field" - and a maximum number - e.g. 4 - and
$app->findqueryvars will return and array containing the numbers of all
submitted variables that had that basename.  If no matching variables are
found, undef will be returned.

=item $app->debug($format, @args)

If the object was created with a "debugvar" variable named, then $app->debug() will 
format a message based on $format and @args and append it to the named template variable,
making it available in the next $app->display() call. If called with a single variable
which is a reference, Data::Dumper will be used to format the reference.

$app->debug() won't store any data if the "debugvar" isn't set. So you can use it to
selectively enable debugging.

=item $app->display($templatefile, $vars[, $output_ref])

Outputs HTTP headers (if not already output) followed by the contents of the
file named by $templatefile. L<Template Toolkit|Template> is used to interpret
the file, and $vars is a hash containing variables which should be made
available to the toolkit. In addition to the variables in $vars,
$app->display() will also add in anything that's been stashed by $app->stash(),
and the contents of anything stored by $app->debug().

If a scalar reference is passed in $output_ref then the header output is
omitted and the processed content is stored into the referenced variable
rather than being output. If any error occurs, the template toolkit error
will be placed in $app->error() and $app->display() will return this error 
too. Otherwise it returns undef.

B<N.B.> Any derived classes should be written to behave in the same manner.

=item $app->panic($message)

Outputs a "Content-Type: text/plain" web header, prints the message and exits. Used
where you've got no option of recovering from an error and just want to exit with an
error. You can also call WebApp::panic($message) if you've not yet managed to create
an application object.

=item $app->error()

Returns the most recently stored internal error in the object.

=item $app->run()

Uses the internally stored state to run whichever collectors and handlers are due to
be run, and displays whichever template is identified by the current state. 

If a state_tracker_name has been registered and the correct value of this variable hasn't 
been posted, the application will be reset back to its top node. If the current node doesn't 
have any handlers, it is assumed to be an exit point of the application and any session data
owned by the application will be destroyed.

=item $app->load($url)

Generates a redirect to the specified URL and exits. If $url is omitted then it
redirects to the the value of $ENV{REQUEST_URI} with any query string stripped
off. If $app has been killed then the redirect will attempt to kill the
session cookie if appropriate. Be warned that some browser have problems with 
handling cookies as part of a redirect, so this part may not work.

=item $app->kill()

Marks the application for destruction. The server side session data will be
destroyed immediately and, if the session is being completely managed by $app,
the next call to $app->headers() (typically from $app->display()) will return a
header which kills the client-side cookie.

=item $app->graph(@dotextras)

This will return a L<graphviz> .dot file describing the structure of the application 
state machine. Good for visualising your application.

=item $app->showgraph($type)

This outputs HTTP headers and a L<graphviz> graph of the application state machine. 
$type can be one of svg, dot or png. B<N.B.> You need to have L<graphviz> installed for this
to work!

=back

=head1 SUBCLASSING

=over

=item $app->templatevars($hash)

If you're subclassing WebApp and overriding the display() method, you should call 
$vars = $self->_templatevars($vars) in your display() method so that WebApp can add
the stash and debugging information to the hash you're going to pass to template toolkit.

=back

=head1 AUTHOR

Designed and implemented by Alun Jones, with loads of input and suggestions from 
Andrew Isherwood and Matt Fullwood.
