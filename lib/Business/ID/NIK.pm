package Business::ID::NIK;

# DATE
# VERSION

use 5.010001;
use warnings;
use strict;

use DateTime;
use Locale::ID::Locality qw(list_id_localities);
use Locale::ID::Province qw(list_id_provinces);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(parse_nik);

our %SPEC;

$SPEC{parse_nik} = {
    v => 1.1,
    summary => 'Parse Indonesian citizenship registration number (NIK)',
    args => {
        nik => {
            summary => 'Input NIK to be validated',
            schema => 'str*',
            pos => 0,
            req => 1,
        },
        check_province => {
            summary => 'Whether to check for known province codes',
            schema  => [bool => default => 1],
        },
        check_locality => {
            summary => 'Whether to check for known locality (city) codes',
            schema  => [bool => default => 1],
        },
    },
};
sub parse_nik {
    my %args = @_;

    state $provinces;
    if (!$provinces) {
        my $res = list_id_provinces(detail => 1);
        return [500, "Can't get list of provinces: $res->[0] - $res->[1]"]
            if $res->[0] != 200;
        $provinces = { map {$_->{bps_code} => $_} @{$res->[2]} };
    }

    my $nik = $args{nik} or return [400, "Please specify nik"];
    my $res = {};

    $nik =~ s/\D+//g;
    return [400, "Not 16 digit"] unless length($nik) == 16;

    $res->{prov_code} = substr($nik, 0, 2);
    if ($args{check_province} // 1) {
        my $p = $provinces->{ $res->{prov_code} };
        $p or return [400, "Unknown province code"];
        $res->{prov_eng_name} = $p->{eng_name};
        $res->{prov_ind_name} = $p->{ind_name};
    }

    $res->{loc_code}  = substr($nik, 0, 4);
    if ($args{check_locality} // 1) {
        my $lres = list_id_localities(
            detail => 1, bps_code => $res->{loc_code});
        return [500, "Can't check locality: $lres->[0] - $lres->[1]"]
            unless $lres->[0] == 200;
        my $l = $lres->[2][0];
        $l or return [400, "Unknown locality code"];
        #$res->{loc_eng_name} = $p->{eng_name};
        $res->{loc_ind_name} = $l->{ind_name};
        $res->{loc_type} = $l->{type};
    }

    my ($d, $m, $y) = $nik =~ /^\d{6}(..)(..)(..)/;
    if ($d > 40) {
        $res->{gender} = 'F';
        $d -= 40;
    } else {
        $res->{gender} = 'M';
    }
    my $today = DateTime->today;
    $y += int($today->year / 100) * 100;
    $y -= 100 if $y > $today->year;
    eval { $res->{dob} = DateTime->new(day=>$d, month=>$m, year=>$y)->ymd };
    if ($@) {
        return [400, "Invalid date of birth: $d-$m-$y"];
    }

    $res->{serial} = substr($nik, 12);
    return [400, "Serial starts from 1, not 0"] if $res->{serial} < 1;

    [200, "OK", $res];
}

1;
# ABSTRACT:

=head1 SYNOPSIS

    use Business::ID::NIK qw(parse_nik);

    my $res = parse_nik(nik => "3273010119800002");


=head1 DESCRIPTION

This module can be used to validate Indonesian citizenship registration number,
Nomor Induk Kependudukan (NIK), or more popularly known as Nomor Kartu Tanda
Penduduk (Nomor KTP), because NIK is displayed on the KTP (citizen identity
card).

NIK is composed of 16 digits as follow:

 pp.DDSS.ddmmyy.ssss

pp.DDSS is a 6-digit area code where the NIK was registered (it used to be but
nowadays not always [citation needed] composed as: pp 2-digit province code, DD
2-digit city/district [kota/kabupaten] code, SS 2-digit subdistrict [kecamatan]
code), ddmmyy is date of birth of the citizen (dd will be added by 40 for
female), ssss is 4-digit serial starting from 1.
