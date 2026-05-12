#!/usr/bin/env perl
# =============================================================
# setup_data.pl
# 生成模拟教授服务器的 400 个文件夹结构
# 运行一次即可: perl setup_data.pl
# =============================================================
use strict;
use warnings;
use File::Path qw(make_path);

my @conferences = (
    "Workshop on Algebraic Process Calculi",
    "International Symposium on Games, Automata, Logics and Formal Verification",
    "Workshop on Structural Operational Semantics",
    "International Conference on Concurrency Theory",
    "Symposium on Trustworthy Global Computing",
    "Workshop on Expressiveness in Concurrency",
    "Conference on Formal Modeling and Analysis of Timed Systems",
    "International Colloquium on Theoretical Aspects of Computing",
    "Workshop on Quantitative Aspects of Programming Languages",
    "Symposium on Symbolic Computation and Mechanized Reasoning",
    "International Conference on Application of Concurrency to System Design",
    "Workshop on Interaction and Concurrency Experience",
    "Conference on Algebra and Coalgebra in Computer Science",
    "International Symposium on Fundamentals of Computation Theory",
    "Workshop on Non-Classical Models of Automata and Applications",
    "Conference on Reversible Computation",
    "International Workshop on Rewriting Logic and Its Applications",
    "Symposium on Real-Time and Embedded Technology",
    "Workshop on Membrane Computing",
    "Conference on Formal Techniques for Distributed Systems",
);

my @editors_first = qw(Rob Luca Jos Wan Anna Bas Paul Ugo Catuscia Frank Ilaria Mohammad Erik Pedro Holger Joost-Pieter);
my @editors_last = ("van Glabbeek","Aceto","Baeten","Fokkink","Ingolfsdottir","Luttik","Levy","Montanari","Palamidessi","Valencia","Castellani","Mousavi","de Vink","D'Argenio","Hermanns","Katoen");

my @places = (
    "Bologna, Italy", "Paris, France", "Enschede, The Netherlands",
    "Cambridge, UK", "Lisbon, Portugal", "Berlin, Germany",
    "Barcelona, Spain", "Vienna, Austria", "Prague, Czech Republic",
    "Edinburgh, UK", "Oxford, UK", "Munich, Germany",
    "Rome, Italy", "Amsterdam, The Netherlands", "Zurich, Switzerland",
);

my @months_name = qw(January February March April May June July August September October November December);

my $total = 400;
print "Creating $total volume folders...\n";

# Create Data/published (list of volume numbers)
make_path("Data");
open(my $pf, '>', "Data/published") or die $!;
for my $i (1..$total) {
    print $pf "$i\n";
}
close($pf);

# Create each volume folder
for my $i (1..$total) {
    my $dir = "Published/$i";
    my $tocdir = "$dir/Papers/toc";
    make_path($tocdir);

    my $ci = $i % scalar(@conferences);
    my $ei1 = $i % scalar(@editors_first);
    my $ei2 = ($i + 3) % scalar(@editors_first);
    my $li1 = $i % scalar(@editors_last);
    my $li2 = ($i + 3) % scalar(@editors_last);
    my $pi = $i % scalar(@places);
    my $year = 2010 + ($i % 15);
    my $month = ($i % 12) + 1;
    my $day = ($i % 28) + 1;

    my $conf = $conferences[$ci];
    my $acronym = "CONF" . sprintf("%03d", $i);

    # Write each file (same as professor's server structure)
    write_file("$dir/volume",      $i);
    write_file("$dir/prefix",      "the");
    write_file("$dir/fullname",    $conf);
    write_file("$dir/acronym",     $acronym);
    write_file("$dir/place",       $places[$pi]);
    write_file("$dir/date",        "$day-" . ($day+2) . " $months_name[$month-1] $year");
    write_file("$dir/affiliation", "");
    write_file("$dir/day",         sprintf("%02d", $day));
    write_file("$dir/month",       sprintf("%02d", $month));
    write_file("$dir/anno",        $year);
    write_file("$dir/editor",      "$editors_first[$ei1]\t$editors_last[$li1]\t\t\n$editors_first[$ei2]\t$editors_last[$li2]\t\t");

    # Papers/toc files
    write_file("$tocdir/arxived",  "https://arxiv.org/abs/" . (1000 + $i) . ".0001");
    write_file("$tocdir/abstract", "These are the proceedings of the $conf ($acronym), held in $places[$pi], $day-" . ($day+2) . " $months_name[$month-1] $year.");

    print "  [$i/$total] $dir\r" if $i % 50 == 0;
}

print "\nDone! Created $total folders in Published/\n";
print "Directory structure:\n";
print "  Data/published         (volume list)\n";
print "  Published/1..400/      (13 files each + Papers/toc/)\n";
print "  Total files: " . ($total * 15) . "\n";

sub write_file {
    my ($path, $content) = @_;
    open(my $fh, '>', $path) or die "Cannot write $path: $!";
    print $fh $content;
    close($fh);
}
