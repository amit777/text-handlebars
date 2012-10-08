package Text::Handlebars::Compiler;
use Any::Moose;

extends 'Text::Xslate::Compiler';

use Try::Tiny;

has '+syntax' => (
    default => 'Handlebars',
);

sub define_helper { shift->parser->define_helper(@_) }

sub _generate_block_body {
    my $self = shift;
    my ($node) = @_;

    my @compiled = map { $self->compile_ast($_) } @{ $node->second };

    unshift @compiled, $self->_localize_vars($node->first)
        if $node->first;

    return @compiled;
}

sub _generate_key {
    my $self = shift;
    my ($node) = @_;

    my $var = $node->clone(arity => 'variable');

    return $self->compile_ast($self->_check_lambda($var));
}

sub _generate_key_field {
    my $self = shift;
    my ($node) = @_;

    my $field = $node->clone(arity => 'field');

    return $self->compile_ast($self->_check_lambda($field));
}

sub _check_lambda {
    my $self = shift;
    my ($var) = @_;

    my $parser = $self->parser;

    my $is_code = $parser->symbol('(name)')->clone(
        arity => 'name',
        id    => '(is_code)',
        line  => $var->line,
    );
    my $run_code = $parser->symbol('(name)')->clone(
        arity => 'name',
        id    => '(run_code)',
        line  => $var->line,
    );

    return $parser->make_ternary(
        $parser->call($is_code, $var->clone),
        $parser->call(
            $run_code,
            $var->clone,
            $parser->vars,
        ),
        $var,
    );
}

sub _generate_include {
    my $self = shift;
    my ($node) = @_;

    my $file = $node->first;
    $file->id($file->id . $self->engine->{suffix})
        unless try { $self->engine->find_file($file->id); 1 };
    return $self->SUPER::_generate_include($node);
}

sub _generate_call {
    my $self = shift;
    my ($node) = @_;

    if ($node->is_helper) {
        my @args;
        my @hash;
        for my $arg (@{ $node->second }) {
            if ($arg->arity eq 'pair') {
                push @hash, $arg->first, $arg->second;
            }
            else {
                push @args, $arg;
            }
        }

        my $parser = $self->parser;

        my $make_hash = $parser->symbol('(name)')->clone(
            arity => 'name',
            id    => '(make_hash)',
            line  => $node->line,
        );

        my $hash = $parser->call($make_hash, @hash);

        unshift @args, $parser->vars;

        if ($node->first->arity eq 'call' && $node->first->first->id eq '(make_block_helper)') {
            push @{ $node->first->second }, $hash;
            $node->second(\@args);
        }
        else {
            $node->second([ @args, $hash ]);
        }
    }

    return $self->SUPER::_generate_call($node);
}

sub _generate_partial {
    my $self = shift;
    my ($node) = @_;

    my $parser = $self->parser;

    my $find_file = $parser->symbol('(name)')->clone(
        arity => 'name',
        id    => '(find_file)',
        line  => $node->line,
    );

    return $self->compile_ast(
        $parser->make_ternary(
            $parser->call($find_file, $node->first->clone),
            $node->clone(
                arity => 'include',
                id    => 'include',
                first => $node->first,
            ),
            $node->clone(
                arity => 'literal',
                id    => '',
            ),
        ),
    );
}

sub _generate_for {
    my $self = shift;
    my ($node) = @_;

    my @opcodes = $self->SUPER::_generate_for(@_);
    return (
        @opcodes,
        $self->opcode('nil'),
    );
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
