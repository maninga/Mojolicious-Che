package Mojolicious::Che;
use Mojo::Base::Che 'Mojolicious';
use Mojo::Loader qw(load_class);

sub new {
  my $app = shift->SUPER::new;
  my %args = @_;
  $app->plugin(Config =>{file => $args{config} || 'Config.pm'});
  my $conf = $app->config;
  
  my $defaults = $conf->{'mojo_defaults'} || $conf->{'mojo'}{'defaults'};
  $app->defaults($defaults)
    if $defaults;
  
  my $secret = $conf->{'mojo_secret'} || $conf->{'mojo_secrets'} || $conf->{'mojo'}{'secret'} || $conf->{'mojo'}{'secrets'} || $conf->{'шифры'} || [rand];
  $app->secrets($secret);

  $app->mode($conf->{'mojo_mode'} || $conf->{'mojo'}{'mode'} || 'development'); # Файл лога уже не переключишь
  #~ $app->log->level( $conf->{'mojo_log_level'} || $conf->{'mojo'}{'log_level'} || 'debug');
  my $log = $conf->{'mojo_log'} || $conf->{'mojo.log'} || $conf->{'mojo'}{'log'};
  $app->log(Mojo::Log->new(%$log))
    if $log;
  #~ warn "Mode: ", $app->mode, "; log level: ", $app->log->level;
  
  my $home = $app->home;
  my $statics = $conf->{'mojo_static_paths'} || $conf->{'mojo.static.paths'} || $conf->{mojo}{static}{paths} || [];
   #~ push @{$app->static->paths}, @{$paths} if $paths;
  push @{$app->static->paths},  $home->rel_dir($_) for @$statics;
  
  my $templates_paths = $conf->{'mojo_renderer_paths'} || $conf->{'mojo.renderer.paths'} || $conf->{mojo}{renderer}{paths} || [];
  push @{$app->renderer->paths}, $home->rel_dir($_) for @$templates_paths;
  
  my $renderer_classes = $conf->{'mojo_renderer_classes'} || $conf->{'mojo.renderer.classes'} || $conf->{mojo}{renderer}{classes} || [];
  push @{$app->renderer->classes}, $_ for grep ! load_class($_), @$renderer_classes;
  
  
  $app->сессия();
  $app->хазы();
  #~ $app->базы();
  #~ $app->запросы();
  $app->плугины();
  $app->хуки();
  $app->спейсы();
  $app->маршруты();
  
  return $app;

}

sub хазы { # Хазы из конфига
  my $app = shift;
  my $conf = $app->config;
  my $h = $conf->{'mojo_has'} || $conf->{'mojo'}{'has'} || $conf->{'хазы'};
  map {
    $app->log->debug("Make the app->has('$_')");
    has $_ => $h->{$_};
  } keys %$h;
}

sub плугины {# Плугины из конфига
  my $app = shift;
  my $conf = $app->config;
  my $plugins = $conf->{'mojo_plugins'} || $conf->{'mojo'}{'plugins'} || $conf->{'плугины'}
    || return;
  map {
    ref $_->[1] eq 'CODE' ? $app->plugin($_->[0] => $app->${ \$_->[1] }) : $app->plugin(@$_);
    $app->log->debug("Enable plugin [$_->[0]]");
  } @$plugins;
}

has dbh => sub {
#~ sub базы {# обрабатывает dbh конфига
  my $app = shift;
  my $conf = $app->config;
  my $c_dbh = $conf->{dbh} || $conf->{'базы'};
  return unless $c_dbh && ref($c_dbh) eq 'HASH' && keys %$c_dbh;
  #~ has dbh => sub {{};}
    #~ unless $app->can('dbh');
  
  my $dbh = {};
  
  my $req_dbi;
  while (my ($db, $opt) = each %$c_dbh) {
    if ($opt->{dbh}) {# && ref $opt eq 'DBI::db'
      $dbh->{$db} ||= $opt->{dbh};
    } else {
      ++$req_dbi
        and require DBI
        unless $req_dbi;
      $dbh->{$db} ||= DBI->connect(@{$opt->{connect}});
      $app->log->debug("Соединился с базой $opt->{connect}[0] app->dbh->{'$db'}");
    }
    
    map {
      $dbh->{$db}->do($_);
    } @{$opt->{do}} if $opt->{do};
    

  }
  return $dbh;
  
};

has sth => sub {

#~ sub запросы {# обрабатывает sth конфига
  my $app = shift;
  my $dbh = eval { $app->dbh }
    or return;
  #~ my %arg = @_;
  my $conf = $app->config;
  
  my $c_dbh = $conf->{dbh} || $conf->{'базы'};
  my $c_sth = $conf->{sth} || $conf->{'запросы'} || {};
  #~ my $c_pos = $conf->{pos} || $conf->{'посы'} || {};
    
  return
    unless ($c_sth && ref($c_sth) eq 'HASH' && keys %$c_sth);
    #~ || ($c_pos && ref($c_pos) eq 'HASH' && keys %$c_pos);

  my $sth = {};
  
  while (my ($db, $opt) = each %$c_dbh) {
    while (my ($st, $sql) = each %{$opt->{sth}}) {
      $sth->{$db}{$st} = $dbh->{$db}->prepare($sql);# $app->sth->{main}{...}
      $app->log->debug("Подготовился запрос [app->sth->{$db}{$st}]");
    }
  }
  
  while (my ($db, $h) = each %$c_sth) {
    while (my ($st, $sql) = each %$h) {
      $sth->{$db}{$st} = $dbh->{$db}->prepare($sql);# $app->sth->{main}{...}
      $app->log->debug("Подготовился запрос [app->sth->{$db}{$st}]");
    }
  }
  
  #~ my $sth_pos;
  #~ while (my ($db, $arr) = each %$c_pos) {
    #~ for my $item (@$arr) {
      #~ $sth_pos ||= $app->_class('DBIx::POS::Sth');
      #~ my $pos_module = $app->_class(ref $item eq 'ARRAY' ? shift @$item : $item);
      #~ $sth->{$db}{$pos_module} = $sth_pos->new($dbh->{$db}, $pos_module->new(ref $item eq 'ARRAY' ? @$item : ()));
      #~ $app->log->debug("Создан STH из POS модуля [$pos_module]");
    #~ }
  #~ }
  
  $sth;
};

  
sub хуки {# Хуки из конфига
  my $app = shift;
  my $conf = $app->config;
  my $hooks = $conf->{'mojo_hooks'} || $conf->{'mojo'}{'hooks'} || $conf->{'хуки'}
     || return;
  while (my ($name, $sub) = each %$hooks) {
  #~ map {
    $app->hook($name => $sub);
    $app->log->debug("Applied hook [$name] from config");
  }

}

sub сессия {
  my $app = shift;
  my $conf = $app->config;
  my $session = $conf->{'mojo_session'} || $conf->{'mojo'}{'session'} || $conf->{'сессия'}
    || return;
  $app->sessions->cookie_name($session->{'cookie_name'});
  
}

sub маршруты {
  my $app = shift;
  my $conf = $app->config;
  my $routes = $conf->{'routes'} || $conf->{'маршруты'}
    or return;
  my $app_routes = $app->routes;
  my $apply_route = sub {
    my $r = shift || $app_routes;
    my ($meth, $arg) = @_;
    my $nr;
    if (my $m = $r->can($meth)) {
      $nr = $r->$m($arg) unless ref($arg);
      $nr = $r->$m(cb => $arg) if ref($arg) eq 'CODE';
      $nr = $r->$m(@$arg) if ref($arg) eq 'ARRAY';
      $nr = $r->$m(%$arg) if ref($arg) eq 'HASH';
      
    }  else {
      $app->log->warn("Can't method [$meth] for route",);
    }
    return $nr;
  };
  
  for my $r (@$routes) {
    my $nr = $apply_route->($app_routes, @$r[0,1])
      or next;
    $app->log->debug("Apply route [$r->[0] $r->[1]]");
    for( my $i = 2; $i < @$r; $i += 2 ) {
      $nr = $apply_route->($nr, @$r[$i, $i+1])
        or next;
    }
  }
}

sub спейсы {
  my $app = shift;
  my $conf = $app->config;
  my $ns = $conf->{'namespaces'} || $conf->{'ns'} || $conf->{'спейсы'}
    || return;
  push @{$app->routes->namespaces}, @$ns;
}

our $VERSION = '0.028';

=pod

=encoding utf8

=head1 Mojolicious::Che

Доброго всем

¡ ¡ ¡ ALL GLORY TO GLORIA ! ! !

=head1 VERSION

0.028

=head1 NAME

Mojolicious::Che - Мой базовый модуль для приложений Mojolicious. Нужен только развернутый конфиг.

=head1 SYNOPSIS

  use Mojo::Base::Che 'Mojolicious::Che' -lib, 'lib';
  
  __PACKAGE__->new(config => 'lib/Config.pm')->start();


=head1 Config file

Порядок строк в этом конфиге соответствует исполнению в модуле!

  {
  'Проект'=>'Тест-проект',
  # mojo => {
    # defaults =>
    # secrets =>
    # mode=>
    # log => {level=>...}
    # static => {paths => [...]},
    # renderer => {paths => [...], classes => [...], },
    # session =>
    # has =>
    # plugins=>
    # hooks =>
  # },
  # Default values for "stash" in Mojolicious::Controller, assigned for every new request.
  mojo_defaults => {layout=>'default',},
  # 'шифры' => [
  mojo_secrets => ['true 123 my app',],
  mojo_mode=> 'development',
  mojo_log_level => 'debug',
  mojo_static_paths => ["static"],
  mojo_renderer_classes => ["Mojolicious::Foo::Fun"],
  # 'сессия' => 
  mojo_session => {cookie_name => 'ELK'},
  
  # 'хазы' => 'Лет 500-700 назад был такой дикий степной торговый жадный народ ХАЗАРЫ. Столицей их "государства" был город Тьмутаракань, где-то на берегу моря Каспия. Потомки этих людей рассыпаны по странам России, Средней Азии, Европы. Есть мнение, что хазары присвоили себе название ЕВРЕИ, но это не те библейские кроткие евреи, а жадные потомки кроманьонцев'
  mojo_has => {
    foo => sub {my $app = shift; return 'is a bar';},
  },
  
  # 'базы' => 
  # will be as has!
  dbh=>{
    'main' => {
      # DBI->connect(dsn, user, passwd, $attrs)
      connect => ["DBI:Pg:dbname=test;", "postgres", undef, {
        ShowErrorStatement => 1,
        AutoCommit => 1,
        RaiseError => 1,
        PrintError => 1, 
        pg_enable_utf8 => 1,
        #mysql_enable_utf8 => 1,
        #mysql_auto_reconnect=>1,
      }],
      # or use Foo::Dbh; external defined dbh
      # dbh => Dbh->dbh,
      # will do on connect
      do => ['set datestyle to "ISO, DMY";',],
      # prepared sth will be as has $app->sth->{<dbh name>}{<sth name>}
      sth => {
        foo => <<SQL,
  select * 
  from foo
  where
    bar = ?;
  SQL
      },
    }
  },
  # 'запросы' => 
  # prepared sth will be as has $app->sth->{<dbh name>}{<sth name>}
  sth => {
    main => {
      now => "select now();"
    },
  },
  
  # 'плугины'=> [
  mojo_plugins=>[ 
      ['Foo::Bar'],
      ['Foo::Plugin' => sub {<...returns config data...>}],
  ],
  # 'хуки' => 
  mojo_hooks=>{
    #~ before_dispatch => sub {1;},
  },
  # 'спейсы' => 
  namespaces => ['Space::Shattle'],
  # 'маршруты' => 
  routes => [
    [get=>'/', to=> {cb=>sub{shift->render(format=>'txt', text=>'Hello!');},}],
  ]
  };

=head1 HAS's

=head2 dbh

Set DBI handlers from config B<dbh> (или B<базы>)

=head2 sth

Set prepared stattements from config B<sth> (или B<запросы>).

=head1 METHODS

Mojolicious::Che inherits all methods from Mojolicious and implements the following new ones.
All methods has nothing on input.

=head2 new()

Top-level method. Setup the atributes of app: B<defaults>, B<secrets>, B<mode>, B<log> from app->config(). Then invoke all other metods in order below.

=head2 сессия()

Session

=head2 хазы()

App has's

=head2 плугины()

Plugins

=head2 хуки()

Hooks

=head2 спейсы()

Namespases

=head2 маршруты()

Routes

=head1 SEE ALSO

L<Mojolicious>

L<Ado>

=head1 AUTHOR

Михаил Че (Mikhail Che), C<< <mche[-at-]cpan.org> >>

=head1 BUGS / CONTRIBUTING

Please report any bugs or feature requests at L<https://github.com/mche/Mojolicious-Che/issues>. Pull requests also welcome.

=head1 COPYRIGHT

Copyright 2016 Mikhail Che.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;