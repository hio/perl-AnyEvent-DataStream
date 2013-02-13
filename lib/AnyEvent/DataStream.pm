package AnyEvent::DataStream;

use 5.006;
use strict;
use warnings FATAL => 'all';

use AnyEvent;
use AnyEvent::Handle;
use Scalar::Util qw(blessed);
use Socket;
use version qw(qv);

our $VERSION = qv('0.01');

our $DEBUG = 0;

{
package AnyEvent::DataStream;
use fields (
	rfh  =>
	wfh  =>
	robj =>
	wobj =>
);
}
{
package AnyEvent::DataStream::Reader;
use base 'fields';
use fields (
	fh =>
	handle  =>
	on_recv =>
	on_exit =>
);
}
{
package AnyEvent::DataStream::Writer;
use base 'fields';
use fields (
	fh =>
);
}

1;

sub new
{
	my $pkg  = shift;
	my %opts = @_;

	#my $r = socketpair(my $rd, my $wr, AF_UNIX, SOCK_STREAM, PF_UNSPEC);
	#$r or die "socketpair: $!";
	#shutdown($rd, 1); # no more writing for reader
	#shutdown($wr, 0); # no more reading for writer

	my $r = pipe(my $rd, my $wr);
	$r or die "pipe: $!";
	select((select($rd), $|=1)[0]);
	select((select($wr), $|=1)[0]);

	$DEBUG and print "rd=".fileno($rd).", wr=".fileno($wr)."\n";
	my $this = $pkg->fields::new();
	$this->{rfh}  = $rd;
	$this->{wfh}  = $wr;
	$this->{robj} = undef;
	$this->{wobj} = undef;
	$this;
}

sub __close_reader
{
	my AnyEvent::DataStream $this = shift or die 'no arg:this';
	close($this->{rfh});
	$this->{rfh}  = undef;
	$this->{robj} = undef;
	$this;
}

sub __close_writer
{
	my AnyEvent::DataStream $this = shift or die 'no arg:this';
	close($this->{wfh});
	$this->{wfh}  = undef;
	$this->{wobj} = undef;
	$this;
}

sub reader_writer
{
	my AnyEvent::DataStream $this = shift or die 'no arg:this';
	my %opts = @_;
	my $rd = $this->__reader(\%opts);
	my $wr = $this->__writer();
	($rd, $wr);
}

sub reader
{
	my AnyEvent::DataStream $this = shift or die 'no arg:this';
	my %opts = @_;
	my $rd = $this->__reader(\%opts);
	$this->__close_writer();
	$rd;
}

sub writer
{
	my AnyEvent::DataStream $this = shift or die 'no arg:this';
	my $wr = $this->__writer();
	$this->__close_reader();
	$wr;
}

sub __reader
{
	my AnyEvent::DataStream $this = shift or die 'no arg:this';
	my $opts = shift or die 'no arg:opts';

	$this->{robj} ||= AnyEvent::DataStream::Reader->_new($this, $opts);
}

sub __writer
{
	my AnyEvent::DataStream $this = shift or die 'no arg:this';
	$this->{wobj} ||= AnyEvent::DataStream::Writer->_new($this);
}

sub _detach_rfh
{
	my AnyEvent::DataStream $this = shift or die 'no arg:this';
	my $fh = $this->{rfh};
	$this->{rfh} = undef;
	$fh;
}

sub _detach_wfh
{
	my AnyEvent::DataStream $this = shift or die 'no arg:this';
	my $fh = $this->{wfh};
	$this->{wfh} = undef;
	$fh;
}

package AnyEvent::DataStream::Reader;
use strict;
use warnings;
use Storable qw(thaw);

sub _new
{
	my $pkg = shift or die 'no arg:pkg';
	my AnyEvent::DataStream $parent = shift or die 'no arg:parent';
	my $opts = shift or die 'no arg:opts';

	my AnyEvent::DataStream::Reader $this = $pkg->new();
	$this->{fh}      = $parent->_detach_rfh();
	$this->{handle}  = undef;
	$this->{on_recv} = $opts->{on_recv} or die 'no reader.on_recv';
	$this->{on_exit} = $opts->{on_exit};

	my $hdl; $hdl = AnyEvent::Handle->new(
		fh => $this->{fh},
		on_read    => sub{ $this->__on_read(); },
		on_timeout => sub{ $this->__destroy(); },
		on_eof     => sub{ $this->__destroy(); },
	);
	$this->{handle}  = $hdl;

	$this;
}

sub DESTROY
{
	my AnyEvent::DataStream::Reader $this = shift or die 'no arg:this';
	$this->__destroy();
}

sub __destroy
{
	my AnyEvent::DataStream::Reader $this = shift or die 'no arg:this';

	if( my $on_exit = $this->{on_exit} )
	{
		$this->{on_exit} = undef;
		$on_exit->();
	}
	if( $this->{handle} )
	{
		$this->{handle} = undef;
	}
	if( $this->{fh} )
	{
		close($this->{fh});
		$this->{fh} = undef;
	}
}

sub __on_read
{
	my AnyEvent::DataStream::Reader $this = shift or die 'no arg:this';

	for(;;)
	{
		my $ref_rbuf = \$this->{handle}->rbuf;
		if( length($$ref_rbuf) < 4 )
		{
			return;
		}
		my $len = unpack("N", $$ref_rbuf);

		if( length($$ref_rbuf) < 4 + $len )
		{
			return;
		}
		my $ref_data = thaw(substr($$ref_rbuf, 4, $len));
		substr($$ref_rbuf, 0, 4+$len, '');
		$this->__deliver($ref_data);
	}
}

sub __deliver
{
	my AnyEvent::DataStream::Reader $this = shift or die 'no arg:this';
	my $ref_data = shift;
	#print Dumper($ref_data); use Data::Dumper;
	$this->{on_recv}->($$ref_data);
}

package AnyEvent::DataStream::Writer;
use strict;
use warnings;
use Storable qw(nfreeze);

sub _new
{
	my $pkg = shift or die 'no arg:pkg';
	my AnyEvent::DataStream $parent = shift or die 'no arg:parent';


	my AnyEvent::DataStream::Writer $this = $pkg->new();
	$this->{fh} = $parent->_detach_wfh();

	$this;
}

sub DESTROY
{
	my AnyEvent::DataStream::Writer $this = shift or die 'no arg:this';
	$this->push_close();
}

sub push_close
{
	my AnyEvent::DataStream::Writer $this = shift or die 'no arg:this';
	if( $this->{fh} )
	{
		close $this->{fh};
		$this->{fh} = undef;
	}
}

sub push_data
{
	my AnyEvent::DataStream::Writer $this = shift or die 'no arg:this';
	my $data = shift;

	my $bin = nfreeze(\$data);
	my $len = length($bin);

	$DEBUG and print "push_data[fd=".fileno($this->{fh})."]: (4+$len)\n";
	my $r = syswrite $this->{fh}, pack("N", $len).$bin;
	defined($r) or die "syswrite: $!";
	$r == $len+4 or die "partial write: $r";

	$this;
}


__END__

=head1 NAME

AnyEvent::DataStream - The great new AnyEvent::DataStream!

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

  use AnyEvent::DataStream;
  use Data::Dumper;
  
  my $cv  = AE::cv;
  my $s   = AnyEvent::DataStream->new();
  my $pid = fork();
  defined($pid) or die "fork: $!";
  if( !$pid )
  {
    # child.
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
  #==> { 'x' => [ 'text' ] };

=head1 METHODS

=head2 new

=head2 reader

=head2 writer

=head2 reader_writer

=head1 AUTHOR

YAMASHINA Hio, C<< <hio at hio.jp> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-anyevent-datastream at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=AnyEvent-DataStream>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc AnyEvent::DataStream


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=AnyEvent-DataStream>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/AnyEvent-DataStream>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/AnyEvent-DataStream>

=item * Search CPAN

L<http://search.cpan.org/dist/AnyEvent-DataStream/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013 YAMASHINA Hio.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of AnyEvent::DataStream
