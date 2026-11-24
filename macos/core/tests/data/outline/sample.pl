# Perl のアウトライン解析のサンプル
package Sample::Module;
use strict;

sub new {
	my $class = shift;
	return bless {}, $class;
}

sub method_one { return 1; }

	sub indented_sub {
	}

# sub commented_out {}
my $text = "sub not_a_sub {";

package main;

sub main_func
{
	print "hello\n";
}
