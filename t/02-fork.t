
use strict;
use warnings;
use AnyEvent::DataStream;
use Data::Dumper;
use Test::More;

caller or __PACKAGE__->__main();

sub __main
{
	plan tests => 1;

	my $cv = AE::cv;
	my $s = AnyEvent::DataStream->new(
	);
	my @recv;
	my $pid = fork();
	defined($pid) or die "fork: $!";
	if( !$pid )
	{
		# child.
		my $wr = $s->writer();
		$wr->push_data("test");
		$wr->push_data({x=>["text"]});
		$wr->push_close();
		exit;
	}
	# parent.
	my $rd = $s->reader(
		on_recv => sub{
			my $data = shift;
			AE::log trace => "on_recv>> ".Dumper($data);
			push(@recv, $data);
		},
		on_exit => sub{
			AE::log trace => "on_exit.\n";
			$cv->send;
		},
	);

	AE::log trace => "main wait...\n";
	$cv->recv;

	is_deeply(\@recv, ['test', {x=>['text']}]);
}

