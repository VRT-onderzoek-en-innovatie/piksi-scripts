#!/usr/bin/env perl

# Copyright (c) 2014, Niels Laukens, VRT <niels.laukens@innovatie.vrt.be>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the VRT nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


use strict;
use warnings;

use Digest::CRC;

use Data::Dumper;

select((select(STDOUT), $|=1)[0]); # Autoflush STDOUT

my %decoder;

$decoder{0xFF00} = sub { # Startup {{{
	print "Startup\n";
}; # }}}

$decoder{0xFFFF} = sub { # Heartbeat {{{
	my ($data) = @_;
	my $flags = unpack "L<", $data;
	printf "Heartbeat, flags 0x%08x\n", $flags;
}; # }}}

$decoder{0x0100} = sub { # GPS Time {{{
	my ($data) = @_;
	my ($wn, $tow, $ns, $flags) = unpack "S<L<l<C", $data;
	printf "GPS Time: week=%d, Time of week=%dms %+dns Flags 0x%02x\n", $wn, $tow, $ns, $flags;
}; # }}}

$decoder{0x0206} = sub { # DOPs {{{
	my ($data) = @_;
	my ($tow, $gdop, $pdop, $tdop, $hdop, $vdop)
		= unpack "L<S<S<S<S<S<", $data;
	printf "DOPs: TOW=%dms G=%0.2f P=%0.2f T=%0.2f H=%0.2f V=%0.2f\n", $tow,
		$gdop*.01, $pdop*.01, $tdop*.01, $hdop*.01, $vdop*.01;
}; # }}}

$decoder{0x0200} = sub { # POS ECEF {{{
	my ($data) = @_;
	my ($tow, $x, $y, $z, $accuracy, $n_sats, $flags)
		= unpack "L<d<d<d<S<CC", $data;
	printf "POS_ECEF: TOW=%dms (%fm, %fm, %fm) +/- %dmm, %d sats, flags %02x\n",
		$tow, $x, $y, $z, $accuracy, $n_sats, $flags;
}; # }}}

$decoder{0x0201} = sub { # POS LLH {{{
	my ($data) = @_;
	my ($tow, $lat, $lon, $height, $h_acc, $v_acc, $n_sats, $flags)
		= unpack "L<d<d<d<S<S<CC", $data;
	printf "POS_LLH: TOW=%dms %fN %fE +/- %dmm, height %fm +/- %dmm, %d sats, flags %02x\n",
		$tow, $lat, $lon, $h_acc, $height, $v_acc, $n_sats, $flags;
}; # }}}

$decoder{0x0205} = sub { # VEL NED {{{
	my ($data) = @_;
	my ($tow, $n, $e, $d, $h_acc, $v_acc, $n_sats, $flags)
		= unpack "L<l<l<l<S<S<CC", $data;
	printf "VEL_NED: TOW=%dms (%d, %d) +/- %d mm/s, height %d +/- %d mm/s, %d sats, flags %02x\n",
		$tow, $n, $d, $h_acc, $d, $v_acc, $n_sats, $flags;
}; # }}}

$decoder{0x0017} = sub { # thread state {{
	my ($data) = @_;
	# ignore
}; # }}}

$decoder{0x0018} = sub { # uart state {{
	my ($data) = @_;
	# ignore
}; # }}}

$decoder{0x0016} = sub { # tracking state {{
	my ($data) = @_;
	my @tracker = map {
			my @d = unpack "CCf<", $_;
			{state => $d[0], prn => $d[1]+1, cn0 => $d[2]};
		} unpack "(a6)*", $data;

	foreach my $i (0..@tracker-1) {
		if( $tracker[$i]->{state} == 0 ) {
			printf "Tracking %d: disabled\n", $i;
		} else {
			printf "Tracking %d: PRN%d status 0x%02x C/N0 %f\n",
				$i, $tracker[$i]->{prn}, $tracker[$i]->{state}, $tracker[$i]->{cn0};
		}
	}
}; # }}}

$decoder{0x0042} = sub { # NEW_OBS {{{
	my ($data, $sender) = @_;
	my ($tow, $wn)
		= unpack "d<S<", substr($data,0,10);
	my @obs = map {
			my @d = unpack "d<d<f<C", $_;
			{pseudorange => $d[0], carrier_phase => $d[1], snr => $d[2], prn => $d[3]+1};
		} unpack "(a21)*", substr($data,10);

	foreach my $i (0..@obs-1) {
		printf "Observation from %04x: %d: PRN%d C/N0 %f: PR=%fm carrier=%f\n",
			$sender, $i, $obs[$i]->{prn}, $obs[$i]->{snr}, $obs[$i]->{pseudorange}, $obs[$i]->{carrier_phase};
	}
}; # }}}

$decoder{0x0010} = sub { # print {{{
	my ($data) = @_;
	printf "Print: %s\n", $data;
}; # }}}


while(<>) {
	unless( m/^(\d+\.\d+): ([0-9a-fA-F]*)$/ ) {
		print "Unparsable line: $_";
		next;
	}
	my @msg = map {hex($_)} unpack("(a2)*", $2);
	my $msg = join '', map{chr($_)} @msg;

	unless( $msg[0] == 0x55 ) {
		print "Invalid header\n";
		next;
	}
	my ($type, $sender, $length) = unpack "S<S<C", substr($msg, 1, 5);
	my $crc_msg = unpack "S<", substr($msg, 6+$length, 2);
	my $crc = Digest::CRC->new(width=>16, init=>0x0000, xorout=>0x0000,
	                           refout=>0, poly=>0x1021, refin=>0, cont=>0);
	# Countrary to the documentation, the preamble is NOT included in the CRC
	$crc->add(substr($msg, 1, 5+$length));
	my $crc_calc = $crc->digest;
	if( $crc_msg != $crc_calc ) {
		printf "CRC mismatch: got %04x, calculated %04x\n", $crc_msg, $crc_calc;
		next;
	}

	if( defined $decoder{$type} ) {
		$decoder{$type}->(substr($msg, 6, $length), $sender);
	} else {
		printf "Unknown message type %04x\n", $type;
	}
}
