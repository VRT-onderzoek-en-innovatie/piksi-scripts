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

use Device::SerialPort;
use Time::HiRes qw(time);

my $port = Device::SerialPort->new($ARGV[0]);
$port->baudrate(1000000);

select((select(STDOUT), $|=1)[0]); # Autoflush STDOUT


my $buffer;
my $starttime = time;
while(1) {
	# Seek to preample
	my $skipped = 0;
	while( length($buffer) > 0 && substr($buffer, 0, 1) ne "\x55" ) {
		$buffer = substr $buffer, 1;
		$skipped++;
	}
	print STDERR "WARNING: skipped $skipped bytes\n" unless $skipped == 0;

	next if length($buffer) < 1+2+2+1+2;
	my $length = ord(substr($buffer, 5, 1));
	next if length($buffer) < 1+2+2+1+$length+2;
	my $message = substr($buffer, 0, 1+2+2+1+$length+2);
	$buffer = substr($buffer, 1+2+2+1+$length+2);

	print "" ,(time - $starttime), ": ";
	print join('', map {sprintf "%02x", ord($_)} split //, $message), "\n";

	redo; # Without reading (at first)
} continue {
	my ($count_in, $string_in) = $port->read(255);
	$buffer .= $string_in;
}
