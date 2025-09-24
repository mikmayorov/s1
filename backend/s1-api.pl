#!/usr/bin/env perl

use warnings;
use strict qw/vars/;
use feature qw/say/;
use autodie;
use utf8;
use open qw/:std :encoding(utf8)/;

use POSIX qw(strftime);
use Data::Dump qw/dump dd/;
use Config::Simple;
use Getopt::Long;
use DBI;

use Mojo::Util qw(trim);
use Mojolicious::Lite -signatures;
use Mojo::JSON qw(encode_json decode_json);

# базовый каталог запуска
$0 =~ /^(.+)\/.+?.pl$/;
our $cmddir = $1;

my $cfgfile = "$cmddir/s1-api.cfg";
my %cfg;

GetOptions( 'config=s' => \$cfgfile );

Config::Simple->import_from($cfgfile, \%cfg) or die Config::Simple->error();

# если yes то пишем логи в файл all.log
if ( $cfg{logfile} eq "yes" ) {
    open (STDOUT, '>>', "$cmddir/all.log");
    open(STDERR, '>&', \*STDOUT);
}

# Поиск адресов
get '/api/search' => sub ($c) {
  my $q = trim($c->param('q') // '');
  return $c->render(
                status => 400,                # Bad Request
                json => { error => 'parameter q is required with min lenght 2 char' }
                ) if $q eq '' || length($q) < 2;

  # Нормализация запроса
  my $norm = lc $q;
  $norm =~ s/\s+/ /g;
  # простые синонимы/сокращения — можно расширять (непонятно надо или нет)
  # $norm =~ s/\bул\b/улица/g;
  # $norm =~ s/\bпр\b/проспект/g;

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

  $c->render(json => { hits => \@hits });
};

app->start;
