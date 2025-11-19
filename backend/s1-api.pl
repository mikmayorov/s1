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
  
  my @hits = (
    { precision => 99, scope => 'gar', type => 'house', full_address => 'Ростовская область, город Таганрог, переулок 14-й Новый, дом 11', gar_objectid=>'79176940', housetype=>'дом' },
    { precision => 99, scope => 'gar', type => 'house', full_address => 'Ростовская область, город Таганрог, переулок Каркасный, дом 11', gar_objectid=>'73266700', housetype=>'дом', apartmentbuilding=>1, numberapartments=>80 },
    { precision => 99, scope => 'gar', type => 'house', full_address => 'Ростовская область, город Таганрог, переулок Каркасный, дом 9', gar_objectid=>'73488337', housetype=>'дом', apartmentbuilding=>1, numberapartments=>71 },
    { precision => 70, scope => 'gar', type => 'house', full_address => 'Ростовская область, Аксайский район, город Аксай, гаражно-строительный кооп. ГСК Фонарь, гараж 48', gar_objectid=>'1482284', housetype=>'гараж' },
    { precision => 80, scope => 'gar', type => 'house', full_address => 'Ростовская область, Каменский район, хутор Верхнеясиновский, улица Космонавтов, домовладение 12', gar_objectid=>'1484455', housetype=>'домовладение' },
    { precision => 80, scope => 'gar', type => 'house', full_address => 'Ростовская область, город Таганрог, переулок Асеевский, здание 29а', gar_objectid=>'1607039', housetype=>'здание' },
    { precision => 65, scope => 'gar', type => 'house', full_address => 'Ростовская область, город Таганрог, улица Большая Бульварная, дом 11', gar_objectid=>'54928973', housetype=>'дом' },
    { precision => 67, scope => 'gar', type => 'stead', full_address => 'Ростовская область, город Таганрог, улица Большая Бульварная, 11', gar_objectid=>'92508014' },
    { precision => 60, scope => 'gar', type => 'address', full_address => 'Краснодарский край, Ейский район, село Александровка, садовое товарищество Планета', gar_objectid=> '319788' },
    { precision => 60, scope => 'gar', type => 'address', full_address => 'Краснодарский край, Ейский район, поселок Мирный', gar_objectid=> '321380' },
    { precision => 60, scope => 'gar', type => 'address', full_address => 'Краснодарский край, Ейский район, поселок Н.Островского, улица Парковая', gar_objectid=> '321449' },
    { precision => 60, scope => 'gar', type => 'apartment', full_address => 'Ростовская область, город Новочеркасск, улица Мацоты С.В., дом 46 владение 3, квартира 65', gar_objectid=> '1800133' },
    { precision => 60, scope => 'gar', type => 'apartment', full_address => 'Ростовская область, город Таганрог, переулок Каркасный, дом 9, квартира 12', gar_objectid=> '73489701' },
    { precision => 60, scope => 'gar', type => 'apartment', full_address => 'Ростовская область, город Ростов-на-Дону, улица Штахановского, дом 16, квартира 28', gar_objectid=> '73489758' },
    { precision => 60, scope => 'gar', type => 'carplace', full_address => 'Ростовская область, город Ростов-на-Дону, переулок Измаильский, дом 43, 7', gar_objectid=> '24187369' },
    { precision => 60, scope => 'gar', type => 'carplace', full_address => 'Ростовская область, город Ростов-на-Дону, переулок Доломановский, дом 19, 113', gar_objectid=> '66639319' },
    { precision => 60, scope => 'gar', type => 'room', full_address => 'Ростовская область, Зимовниковский район, станица Кутейниковская, переулок Колхозный, дом 2, квартира 1, комната 1', gar_objectid=> '4809431' },
    { precision => 60, scope => 'gar', type => 'room', full_address => 'Ростовская область, город Таганрог, улица Театральная, дом 17-2, квартира 5, помещение 69', gar_objectid=> '97944774' }
    );

  $c->render(json => \@result);
};

app->start;
