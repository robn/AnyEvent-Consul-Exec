package AnyEvent::Consul::Exec;

# ABSTRACT: Execute a remote command across a Consul cluster

use 5.020;
use warnings;
use strict;
use experimental qw(postderef);

use Consul 0.021;
use AnyEvent;
use AnyEvent::Consul;
use JSON::MaybeXS;
use Type::Params qw(compile);
use Types::Standard qw(ClassName Dict Str Optional CodeRef slurpy);

sub new {
  state $check = compile(
    ClassName,
    slurpy Dict[
      command    => Str,
      on_submit  => Optional[CodeRef],
      on_ack     => Optional[CodeRef],
      on_output  => Optional[CodeRef],
      on_exit    => Optional[CodeRef],
      on_done    => Optional[CodeRef],
      on_error   => Optional[CodeRef],
    ],
  );
  my ($class, $self) = $check->(@_);
  map { $self->{$_} //= sub {} } qw(on_submit on_ack on_output on_exit on_done on_error);
  return bless $self, $class;
}

sub _wait_responses {
  my ($self, $index) = @_;

  $self->{_c}->kv->get_all(
    "_rexec/$self->{_sid}",
    index => $index, 
    cb => sub {
      my ($kv, $meta) = @_;
      my @changed = grep { $_->modify_index > $index } $kv->@*;

      for my $kv (@changed) {
        my ($key) = $kv->key =~ m{^_rexec/$self->{_sid}/(.+)};
        unless ($key) {
          warn "W: consul told us '".$kv->key."' changed, but we aren't interested in it, consul bug?\n";
          next;
        }

        if ($key eq 'job') {
          $self->{on_submit}->();
          next;
        }

        my ($node, $act, $id) = split '/', $key, 3;
        unless ($act) {
          warn "W: malformed rexec response: $key\n";
        }

        if ($act eq 'ack') {
          $self->{_nack}++;
          $self->{on_ack}->($node);
          next;
        }

        if ($act eq 'out') {
          $self->{on_output}->($node, $kv->value);
          next;
        }

        if ($act eq 'exit') {
          $self->{_nexit}++;
          $self->{on_exit}->($node, $kv->value);
          if ($self->{_nack} == $self->{_nexit}) {
            # XXX super naive. there might be some that haven't acked yet
            #     should schedule done for a lil bit in the future
            $self->{_done} = 1;
            $self->_cleanup(sub { $self->{on_done}->() });
          }
          next;
        }

        warn "W: $node: unknown action: $act\n";
      }

      $self->_wait_responses($meta->index) unless $self->{_done};
    },
  );
}
sub _fire_event {
  my ($self) = @_;
  my $payload = {
    Prefix  => "_rexec",
    Session => $self->{_sid},
  };
  $self->{_c}->event->fire(
    "_rexec",
    payload => encode_json($payload),
    cb => sub { $self->_wait_responses(0) },
  );
}

sub _setup_job {
  my ($self) = @_;
  my $job = {
    Command => $self->{command},
    Wait    => 2000000000,          # XXX
  };
  $self->{_c}->kv->put("_rexec/$self->{_sid}/job", encode_json($job), cb => sub { $self->_fire_event });
}

sub _start_session {
  my ($self) = @_;
  $self->{_c}->session->create(Consul::Session->new(name => "exec", ttl => "10s"), cb => sub {
    $self->{_sid} = shift;
    $self->{_refresh_guard} = AnyEvent->timer(after => "5s", interval => "5s", cb => sub {
      $self->{_c}->session->renew($self->{_sid});
    });
    $self->_setup_job;
  });
}

sub _cleanup {
  my ($self, $cb) = @_;
  delete $self->{_refresh_guard};
  if ($self->{_sid}) {
    $self->{_c}->kv->delete("_rexec/$self->{_sid}", recurse => 1, cb => sub {
      delete $self->{_sid};
      delete $self->{_c};
      $cb->();
    });
  }
  else {
    delete $self->{_sid};
    delete $self->{_c};
    $cb->();
  }
}

sub start {
  my ($self) = @_;
  $self->{_c} = AnyEvent::Consul->new(error_cb => sub {
    my ($err) = @_;
    $self->_cleanup(sub { $self->{on_error}->($err) });
  });
  $self->_start_session;
  return;
}

1;
