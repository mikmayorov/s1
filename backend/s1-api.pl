#!/usr/bin/env perl

use warnings;
use strict;
use feature ':all';
use utf8;
use open qw/:std :encoding(utf8)/;

use POSIX qw(strftime);
use DDP; # аналог Data::Dump
use Config::Simple;
use Getopt::Long;
use DBI;

use Mojolicious::Lite -signatures;
use Mojo::JSON qw(encode_json decode_json);

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

my $dbh = DBI->connect('dbi:Pg:dbname=' . $cfg{'db.name'} . ';host=' . $cfg{'db.host'}, $cfg{'db.user'}, $cfg{'db.password'},
                       { PrintWarn => 0,
                         PrintError => 0,
                         RaiseError => 1,
                         AutoCommit => 1,
                         ShowErrorStatement => 1,
                         pg_enable_utf8     => 1,
                         HandleError        => sub {
                              my ($err, $h, $ret) = @_;   # $h - handle (dbh или sth)
                              my $sql = eval { $h->{Statement} } // '';
                              # app->log->error("DBI error: $err; SQL: $sql");
                              # вернуть 0, чтобы ошибка дальше пошла в RaiseError (die)
                              return 0; },
                        }
                         ) || die "Не могу соедениться с базой данных";

# проверка что api 
get '/api/ping' => sub {
    my $c = shift;
    $c->render(text => 'pong');
};

# универсальный поиск
get '/api/search' => sub ($c) {
  my $q = Mojo::Util::trim($c->param('q') // '');

  $c->app->log->debug("search called: q=$q");

  return $c->render(
                status => 400,                # Bad Request
                json => { error => 'parameter q is required with min lenght 2 char' }
                ) if $q eq '' || length($q) < 3;

  my $sth = $dbh->prepare('SELECT row_number() over () index_number, * FROM search_gar(?)');
  $sth->execute($q);
  my $rows = $sth->fetchall_arrayref({});
  $sth->finish;

  my @result;
  push @result, { scope => 'gar', number_results => scalar(@$rows), data => $rows };

  $c->render(json => \@result);
};

app->start;
