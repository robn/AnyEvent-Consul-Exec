#!perl

use 5.020;
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Consul;

use AnyEvent;
use AnyEvent::Consul;
use AnyEvent::Consul::Exec;

my $tc = eval { Test::Consul->start };

SKIP: {
  skip "consul test environment not available", 5, unless $tc;
  
  my $cv = AE::cv;

  my $e = AnyEvent::Consul::Exec->new(
    consul_args => [ port => $tc->port ],

    command => 'uptime',

    on_submit => sub {
      ok 1, "job submitted";
    },

    on_ack => sub {
      my ($node) = @_;
      ok 1, "$node: ack";
    },

    on_output => sub {
      my ($node, $output) = @_;
      ok 1, "$node: output";
    },

    on_exit => sub {
      my ($node, $rc) = @_;
      ok 1, "$node: exit: $rc";
    },

    on_done => sub {
      ok 1, "job done";
      $cv->send;
    },

    on_error => sub {
      my ($err) = @_;
      ok 1, "error: $err";
    },
  );

  $e->start;
  $cv->recv;
}

done_testing;
