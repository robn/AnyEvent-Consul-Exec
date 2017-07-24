[![Build Status](https://secure.travis-ci.org/robn/AnyEvent-Consul-Exec.png)](http://travis-ci.org/robn/AnyEvent-Consul-Exec)

# NAME

AnyEvent::Consul::Exec - Execute a remote command across a Consul cluster

# SYNOPSIS

    use AnyEvent;
    use AnyEvent::Consul::Exec;
    
    my $cv = AE::cv;
    
    my $e = AnyEvent::Consul::Exec->new(
        
        # command to run
        command => 'uptime',
        
        # called once job is submitted to Consul
        on_submit => sub {
            say "job submitted";
        },
        
        # called as each target node starts to process the job
        # multiple calls, once per node
        on_ack => sub {
            my ($node) = @_;
            say "$node: ack";
        },
        
        # called when a node has output from the job
        # can be called zero or more times per node, as more output
        # becomes available
        on_output => sub {
            my ($node, $output) = @_;
            say "$node: output:";
            say "$node> $_" for split("\n", $output);
        },
        
        # called when the node completes a job
        # multiple calls, one per node
        on_exit => sub {
            my ($node, $rc) = @_;
            say "$node: exit: $rc";
        },
        
        # called once all nodes have reported completion
        # object is unusable past this point
        on_done => sub {
            say "job done";
            $cv->send;
        },
        
        # called if an error occurs anywhere during processing (not command errors)
        # typically called if Consul is unable to service requests
        # object is unusable past this point
        on_error => sub {
            my ($err) = @_;
            say "error: $err";
            $cv->send;
        },
    );
    
    # begin execution
    $e->start;

    $cv->recv;

# DESCRIPTION

AnyEvent::Consul::Exec is an interface to Consul's "exec" agent function. This
is the same thing you get when you run [consul exec](https://www.consul.io/docs/commands/exec.html).

`consul exec` is great, but its output is text-based, making it awkward to
parse to determine what happened on each node that ran the command.
`AnyEvent::Consul::Exec` replaces the client portion with a library you can
use to get info about what is happening on each node as it happens.

As the name implies, it expects to be run inside an [AnyEvent](https://metacpan.org/pod/AnyEvent) event loop.

# BASICS

Start off by instantiating a `AnyEvent::Consul::Exec` object with the command
you want to run:

    my $e = AnyEvent::Consul::Exec->new(
        command => 'uptime',
    );

Then call `start` to kick it off:

    $e->start;

As the `AnyEvent` event loop progresses, the command will be executed on
remote nodes. Output and results of that command on each node will be posted to
callbacks you can optionally provide to the constructor.

When calling the constructor, you can include the `consul_args` option with an
arrayref as a value. Anything in that arrayref will be passed as-is to the
`AnyEvent::Consul` constructor. Use this to set the various client options
documented in [AnyEvent::Consul](https://metacpan.org/pod/AnyEvent::Consul) and [Consul](https://metacpan.org/pod/Consul).

# CALLBACKS

`AnyEvent::Consul::Exec` will arrange for various callbacks to be called as
the command is run on each node and its output and exit code returned. Set this
up by passing code refs to the constructor:

- `on_submit`

    Called when the command is fully accepted by Consul (ie in the KV store, ready
    for nodes to find).

- `on_ack($node)`

    Called for each node as they notice the command has been entered into the KV
    store and start running it.

- `on_output($node, $output)`

    Called when a command emits some output. May be called multiple times per node,
    or not at all if the command has no output.

- `on_exit($node, $rc)`

    Called when a command completes.

- `on_done`

    Called when all remote commands have completed. After this call, the object is
    no longer useful.

- `on_error($err)`

    Called if an error occurs while communicating with Consul (local agent
    unavailable, quorum loss, etc). After this call, the object is no longer
    useful.

# CAVEATS

Consul's remote execution protocol is internal to Consul itself and is not
documented. This module has been confirmed to work in Consul 0.9.0 (the latest
release at the time of writing). The Consul authors [may change the underlying
mechanism](https://github.com/hashicorp/consul/issues/1120) in the future, but
this module should continue to work.

# SUPPORT

## Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at [https://github.com/robn/AnyEvent-Consul-Exec/issues](https://github.com/robn/AnyEvent-Consul-Exec/issues).
You will be notified automatically of any progress on your issue.

## Source Code

This is open source software. The code repository is available for
public review and contribution under the terms of the license.

[https://github.com/robn/AnyEvent-Consul-Exec](https://github.com/robn/AnyEvent-Consul-Exec)

    git clone https://github.com/robn/AnyEvent-Consul-Exec.git

# AUTHORS

- Rob N ★ <robn@robn.io>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2017 by Rob N ★ and was supported by FastMail
Pty Ltd.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
