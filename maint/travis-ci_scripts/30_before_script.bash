#!/bin/bash

source maint/travis-ci_scripts/common.bash
if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

if [[ "$CLEANTEST" = "true" ]]; then
  # get the last inc/ off cpan - we will get rid of MI
  # soon enough, but till then this will do
  # the point is to have a *really* clean perl (the ones
  # we build are guaranteed to be clean, without side
  # effects from travis preinstalls)

  # trick cpanm into executing true as shell - we just need the find+unpack
  run_or_err "Downloading DBIC inc/ from CPAN" \
    "SHELL=/bin/true cpanm --look DBIx::Class"

  mv ~/.cpanm/latest-build/DBIx-Class-*/inc .

  # older perls do not have a CPAN which understands configure_requires
  # properly and what is worse a `cpan Foo` run exits with 0 even if some
  # modules failed to install
  # The first CPAN which is somewhat sane is around 1.94_56 (perl 5.12)
  # The problem is that the first sane version also brings a *lot* of
  # deps with it, notably things like YAML and HTTP::Tiny
  # The goal of CLEANTEST is to have as little extra stuff installed as
  # possible, mainly to catch "but X is perl core" mistakes
  # So instead we still use our stock (possibly old) CPAN, and add some
  # handholding
  CPAN_is_sane || \
    run_or_err "Pre-installing ExtUtils::MakeMaker and Module::Build" \
      "cpan ExtUtils::MakeMaker Module::Build"

  if ! perl -MModule::Build -e 1 &> /dev/null ; then
    echo_err -e "Module::Build installation failed\n$LASTOUT"
    exit 1
  fi

  # DBI has by far the longest test runtime - run less tests
  # FIXME horrible horrible hack, need to implement in DBI itself
  run_or_err "Downloading latest DBI distdir from CPAN" \
    "SHELL=/bin/true cpanm --look DBI"
  cd ~/.cpanm/latest-build/DBI-*/
  perl -p -i -e 's/(create_.+?_tests) => 1/$1 => 0/' Makefile.PL
  run_or_err "Pre-installing DBI, but running less tests" "perl Makefile.PL && make && make test && make install"
  cd - &>/dev/null

else
  # we will be running all dbic tests - preinstall lots of stuff, run basic tests
  # using SQLT and set up whatever databases necessary
  export DBICTEST_SQLT_DEPLOY=1

  # do the preinstall in several passes to minimize amount of cross-deps installing
  # multiple times, and to avoid module re-architecture breaking another install
  # (e.g. once Carp is upgraded there's no more Carp::Heavy)
  #
  parallel_installdeps_notest ExtUtils::MakeMaker
  parallel_installdeps_notest Carp
  parallel_installdeps_notest Module::Build
  parallel_installdeps_notest Module::Runtime ExtUtils::Depends File::Spec Data::Dumper
  parallel_installdeps_notest Test::Exception LWP
  parallel_installdeps_notest Test::Fatal Test::Warn bareword::filehandles
  parallel_installdeps_notest namespace::clean Class::XSAccessor MRO::Compat
  parallel_installdeps_notest DBD::SQLite Moo Class::Accessor::Grouped
  parallel_installdeps_notest Module::Install DateTime::Format::Strptime
  parallel_installdeps_notest JSON::DWIW JSON JSON::XS Test::Pod::Coverage Test::EOL
  parallel_installdeps_notest MooseX::Types JSON::Any Class::DBI

  if [[ -n "DBICTEST_FIREBIRD_DSN" ]] ; then 
    # the official version is full of 5.10-isms, but works perfectly fine on 5.8
    # pull in our patched copy
    run_or_err "Fetching patched DBD::Firebird" \
      "git clone https://github.com/dbsrgits/perl-dbd-firebird-5.8.git ~/dbd-firebird"

    # the official version is very much outdated and does not compile on 5.14+
    # use this rather updated source tree (needs to go to PAUSE):
    # https://github.com/pilcrow/perl-dbd-interbase
    run_or_err "Fetching patched DBD::InterBase" \
      "git clone https://github.com/dbsrgits/perl-dbd-interbase ~/dbd-interbase"

    parallel_installdeps_notest ~/dbd-interbase/ ~/dbd-firebird/
  fi

fi

# generate the makefile which will have different deps depending on
# the runmode and envvars set above
run_or_err "Configure on current branch" "perl Makefile.PL"

# install (remaining) dependencies, sometimes with a gentle push
if [[ "$CLEANTEST" = "true" ]]; then
  # we may need to prepend some stuff to that list
  HARD_DEPS="$(echo $(make listdeps))"

  # this is a fucked CPAN - won't understand configure_requires of
  # various pieces we may run into
  CPAN_is_sane || HARD_DEPS="ExtUtils::Depends B::Hooks::OP::Check $HARD_DEPS"

##### TEMPORARY WORKAROUNDS

  # not sure what's going on here yet
  perl -M5.008008 -e 1 &> /dev/null || \
    parallel_installdeps_notest multidimensional bareword::filehandles

  # work around Params::Validate not having a Makefile.PL so really old
  # toolchains can not figure out what the prereqs are ;(
  # Need to do more research before filing a bug requesting Makefile inclusion
  perl -M5.008008 -e 1 &> /dev/null || \
    HARD_DEPS="$(extract_prereqs Params::Validate) $HARD_DEPS"

##### END TEMPORARY WORKAROUNDS

  run_or_err "Installing/testing dependencies (may take up to 10 minutes): $HARD_DEPS" "cpan $HARD_DEPS"

  # this is a fucked CPAN - save the log as we may need it
  CPAN_is_sane || INSTALLDEPS_OUT="$LASTOUT"

else
  # listalldeps is deliberate - will upgrade everything it can find
  parallel_installdeps_notest $(make listalldeps)
fi

echo_err "$(tstamp) Dependency configuration finished"
# this will display list of available versions
perl Makefile.PL

# make sure we got everything we need
if [[ -n "$(make listdeps)" ]] ; then
  echo_err "$(tstamp) Not all deps installed - something went wrong :("
  sleep 1 # without this the echo below confuses the console listener >.<
  CPAN_is_sane || echo_err -e "Outdated CPAN.pm used - full logs follows\n$INSTALLDEPS_OUT\n\nSearch for 'NOT OK' in the text above\n\nDeps still missing:"
  sleep 3 # without this the above echo confuses the console listener >.<
  make listdeps
  exit 1
fi

# announce what are we running
echo_err "
===================== DEPENDENCY CONFIGURATION COMPLETE =====================
$(tstamp) Configuration phase seems to have taken $(date -ud "@$SECONDS" '+%H:%M:%S') (@$SECONDS)

= CPUinfo
$(perl -0777 -p -e 's/.+\n\n(?!\z)//s' < /proc/cpuinfo)

= Meminfo
$(free -m -t)

= Environment
$(env | grep -P 'TEST|TRAVIS|PERL|DBIC' | LC_ALL=C sort | cat -v)

= Perl in use
$(perl -V)
============================================================================="
