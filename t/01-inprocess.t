
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
	my ($rd, $wr) = $s->reader_writer(
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
	$wr->push_data("test");
	$wr->push_data({x=>["text"]});
	$wr->push_close();

	AE::log trace => "main wait...\n";
	$cv->recv;

	is_deeply(\@recv, ['test', {x=>['text']}]);
}

