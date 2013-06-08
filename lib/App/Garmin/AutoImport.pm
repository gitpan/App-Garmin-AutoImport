package App::Garmin::AutoImport;

=head1 NAME

App::Garmin::AutoImport - Import data from a Garmin device

=head1 VERSION

0.90

=head1 DESCRIPTION

The C<garmin-autoimport> application is used to import data from a Garmin
device such as the Forerunner 305, but will work with any other Garmin
device supported by
L<garmin-forerunner-tools|https://launchpad.net/ubuntu/+source/garmin-forerunner-tools>.

The application is supposed to be autostarted in a destop environment (such as
L<Ubuntu|http://ubuntu.com>). It will then detect when a Garmin device is
connected and start downloading new track logs from the device and save them to
C<Documents/garmin> in the current user's home directory.

This program can also be installed from a debian package. This is highly
suggested, since the Perl modules required to run this application might be
difficult to install, even with tools like L<cpanm|App::cpanminus>.

The debian package can be found here:
L<https://github.com/jhthorsen/app-garmin-autoimport/raw/master/dist/garmin-autoimport_0.90_all.deb>

=head1 SYNOPSIS

  use App::Garmin::AutoImport;
  exit App::Garmin::AutoImport->new->run;

Or use the C<garmin-autoimport> application bundled to this package.

=head1 ENVIRONMENT VARIABLES

=over 4

=item * NO_NOTIFICATIONS

Will not load L<Gtk2::Notify> and will not send notifications to the desktop
environment.

=item * GARMIN_ID_VENDOR

Set this if you got a Garmin device which does not have the USB vendor ID
"0x091e".

=back

=cut

use strict;
use warnings;
use Device::USB;
use constant NO_NOTIFICATIONS => $ENV{NO_NOTIFICATIONS} ? 1 : 0;
use constant GARMIN_ID_VENDOR => $ENV{GARMIN_ID_VENDOR} || '0x091e';
use constant GARMIN_SAVE_RUNS_BIN
  => $ENV{GARMIN_SAVE_RUNS_BIN}
  || (map { "$_/garmin_save_runs" } grep { -x "$_/garmin_save_runs" } split /:/, $ENV{PATH})[0]
  ;

our $VERSION = '0.90';

unless(NO_NOTIFICATIONS) {
  require Gtk2::Notify;
  Gtk2::Notify->init('garmin-autoimport');
}

=head1 ATTRIBUTES

=head2 id_product

Returns the USB ID of the Garmin product. Default is 0.

=head2 id_vendor

Returns the USB ID of the Garmin vendor. Default is the C<GARMIN_ID_VENDOR>
L</ENVIRONMENT> variable.

=cut

sub id_product { $_[0]->{id_product} }
sub id_vendor { $_[0]->{id_vendor} }

sub _usb {
  $_[0]->{_usb} ||= do {
    my $usb = Device::USB->new;
    $usb->debug_mode($ENV{USB_DEBUG_MODE}) if $ENV{USB_DEBUG_MODE};
    $usb;
  };
}

=head1 METHODS

=head2 new

  $self = $class->new(\%args);
  $self = $class->new(%args);

Object constructor. C<%args> can have:

=over 4

=item * id_product

Defaults to 0, which enable it to be set by L</auto_detect_device>.

=item * id_vendor

Defaults to L</GARMIN_ID_VENDOR>.

=item * output_dir

Defaults to C<$ENV{HOME}/Documents/garmin>.

=back

=cut

sub new {
  my $class = shift;
  my $self = bless @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {}, ref $class || $class;

  $self->{id_product} ||= 0;
  $self->{id_vendor} ||= hex GARMIN_ID_VENDOR;
  $self->{output_dir} ||= "$ENV{HOME}/Documents/garmin";
  $self;
}

=head2 auto_detect_device

  $self->auto_detect_device;

This method starts by checking if a Garmin device is already connected. If not
found, it will check for a new device and use the first that is found.

This method sets L</id_product> and L<id_vendor>.

=cut

sub auto_detect_device {
  my $self = shift;
  my @before = $self->_usb->list_devices;
  my(@after, $guard);

  for my $b (@before) {
    next if $b->idVendor ne $self->id_vendor;
    $self->{id_product} = $b->idProduct;
  }

  if(!$self->{id_product}) {
    while($guard++ < 20) {
      @after = $self->_usb->list_devices;
      last if @after != @before;
      sleep 1;
    }

    DEVICE:
    for my $a (@after) {
      for my $b (@before) {
        next DEVICE if $a->idVendor eq $b->idVendor and $a->idProduct eq $b->idProduct;
      }
      $self->{id_product} = $a->idProduct;
      last DEVICE;
    }
  }

  if($self->{id_product}) {
    warn "id_vendor=$self->{id_vendor}, id_product=$self->{id_product}\n";
  }
  elsif(@after != @before) {
    $self->notify('You connected a USB device, but not a Garmin product');
  }

  $self;
}

=head2 notify

  $self->notify($message);
  $self->notify($title, $message);

Notify the user using L<Gtk2::Notify> which sends popup notifictions to the
desktop environment.

=cut

sub notify {
  my $self = shift;
  my $message = pop;
  my $title = shift || 'garmin-autoimport';

  warn "[notify] $title: $message\n";
  Gtk2::Notify->new($title, $message)->show unless NO_NOTIFICATIONS;
}

=head2 run

  $self->run;

Will run the application inside a never ending loop. Calls
L</auto_detect_device> until L</id_product> is detected and starts
C<garmin_save_runs> once the Garmin device is connected.

=cut

sub run {
  my $self = shift;

  if($self->_already_running) {
    return 0;
  }

  unless(-x GARMIN_SAVE_RUNS_BIN) {
    $self->notify('Cannot execute "garmin_save_runs"');
    return 2;
  }

  while(1) {
    $self->auto_detect_device unless $self->id_product;
    $self->_run if $self->id_product;
    sleep 1;
  }

  return 0;
}

sub _connected {
  my $self = shift;
  my @new;

  $self->notify('Garmin device connected. Starting import...');

  local $ENV{GARMIN_SAVE_RUNS} = $self->{output_dir};
  if(open my $GARMIN, '-|', GARMIN_SAVE_RUNS_BIN) {
    while(<$GARMIN>) {
      print $_;
      next if /Skipped:/;
      push @new, $1 if /Wrote:\s*(\S+)/;
    }
    $self->notify(sprintf '%s new files got imported to %s', int @new, $self->{output_dir});
  }
  else {
    $self->notify(sprintf 'Could not start %s: %s', GARMIN_SAVE_RUNS_BIN, $!);
  }
}

sub _already_running {
  my $self = shift;
  my $pid_file = '/tmp/garmin-autoimport.pid';
  my $pid;

  if(-r $pid_file) {
    open my $PID, '<', '/tmp/garmin-autoimport.pid';
    if($pid = readline $PID) {
      chomp $pid;
      if(kill 0, $pid) {
        $self->notify('Already running');
        return 1;
      }
    }
  }

  open my $PID, '>', '/tmp/garmin-autoimport.pid';
  print $PID $$;
  return 0;
}

sub _run {
  my $self = shift;

  if($self->_usb->find_device($self->id_vendor, $self->id_product)) {
    $self->_connected unless $self->{connected}++;
  }
  else {
    $self->{connected} = 0;
  }
}

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
