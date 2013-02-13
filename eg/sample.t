
use strict;
use warnings;
use AnyEvent::DataStream;
use Data::Dumper;

caller or __PACKAGE__->__main();

sub __main
{
	my $cv = AE::cv;
	my $s = AnyEvent::DataStream->new();
	my $pid = fork();
	defined($pid) or die "fork: $!";
	if( !$pid )
	{
		$s->writer()->push_data({x=>["text"]});
		exit;
	}
	# parent.
	my $rd = $s->reader(
		on_recv => sub{
			$cv->send(shift);
		},
	);

	print Dumper($cv->recv);
}

