#!/usr/bin/env perl

use warnings;
use strict;
use feature ':all';
use utf8;
use open qw/:std :encoding(utf8)/;

use POSIX qw(strftime);
use Config::Simple;
use Getopt::Long;
# use DBI;

use Mojolicious::Lite -signatures;
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Pg;

# базовый каталог запуска
$0 =~ /^(.+)\/.+?.pl$/;
our $cmddir = $1;

my $cfgfile = "$cmddir/s1-api.conf";
my %cfg;

GetOptions( 'config=s' => \$cfgfile );

Config::Simple->import_from($cfgfile, \%cfg);
# небольшие проблемы с модулем Config::Simple (если переменная массив, то удаляем из него значения undef)
map { if (ref eq 'ARRAY') { @$_ = grep { defined } @$_ } } values %cfg;

# если yes то пишем логи в файл all.log
if ( $cfg{'app.log2file'} eq 'yes' ) {
    open (STDOUT, '>>', "$cmddir/all.log");
    open(STDERR, '>&', \*STDOUT);
}

# настройка http сервера hypnotoad
map { if ( /^hypnotoad\.(.+)/ ) { app->config->{hypnotoad}{$1} = $cfg{$_}; } } keys %cfg;

app->hook(around_dispatch => sub {
    my ($next, $c) = @_;
    my $res;

    eval {
        $res = $next->();
    };
    if ($@) {
        $c->app->log->error("UNCAUGHT ERROR: $@");
        return $c->render(
            status => 500,
            json   => { error => "Internal server error" },
        );
    }

    return $res;
});

helper pg => sub ($c) {
  state $pg = do {
    my $pg = Mojo::Pg->new( $cfg{'db.s1_url'});

    $pg->max_connections($cfg{'db.s1_poll'} // 5);
    $pg->options({
      PrintWarn         => 0,
      PrintError        => 0,
      RaiseError        => 1,
      ShowErrorStatement => 1,
      pg_enable_utf8    => 1,
      pg_auto_reconnect => 1,
    });

    $pg;
  };
};


# проверка что api 
get '/api/ping' => sub {
    my $c = shift;
    $c->render(text => 'pong');
};

# универсальный поиск
get '/api/search' => sub ($c) {

  # нормализация входных параметров
  my $q = Mojo::Util::trim($c->param('q') // '');
  $q =~ s/\s+/ /g;

  $c->app->log->debug("search called: q=$q");

  my $qlen = length($q);
  ($qlen < 3 || $qlen > 100) && return $c->render(
                status => 400,                # Bad Request
                json => { error => 'parameter q is required with min/max lenght 2/100 char' }
                );

  # row_number() over () index_number - если прийдеться отдельно сохранять индекс сортированого столбца
  my $rows;
  eval {
    $rows = $c->pg->db->query('SELECT * FROM search_gar(?)', $q)->hashes->to_array;
  };

  if ($@) {
    $c->app->log->error("DB error in /api/search: $@");
    return $c->render(
      status => 503,
      json   => { error => 'database is temporarily unavailable' },
    );
  }

  my @result;
  push @result, { scope => 'gar', number_results => scalar(@$rows), data => $rows };

  $c->render(json => \@result);
};

app->start;
