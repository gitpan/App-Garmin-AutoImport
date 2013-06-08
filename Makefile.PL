use ExtUtils::MakeMaker;

WriteMakefile(
  NAME => 'App-Garmin-AutoImport',
  AUTHOR => 'Jan Henning Thorsen <jhthorsen@cpan.org>',
  EXE_FILES => ['script/garmin-autoimport'],
  VERSION_FROM => 'lib/App/Garmin/AutoImport.pm',
  PREREQ_PM => {
    q(Device::USB) => 0.35,
    q(Gtk2::Notify) => 0.05,
  },
  test => {
    TESTS => 't/*.t',
  }
);
