package MassSpec::ViewSpectrum;

use strict;
use warnings;

use Carp;
use GD;
use GD::Graph::lines;
use GD::Graph::lines;
use GD::Graph::colour qw(:lists :colours);

our @ISA = qw(GD::Graph::Error);

our $VERSION = '0.02';


# Preloaded methods go here.
my %defaultannotationsmatching = (
 '^y$|^y | y$| y ' => 'y',
 '^b$|^b | b$| b ' => 'b',
 'internal' => 'internal',
 '^$' => 'none'
);


my %defaultcolormap = (
	'y' => 'red',
	'b' => 'blue',
	'internal' => 'green',
	'other' => 'dbrown',
	'none' => 'black'
);


my %Defaults = (
	width => 500,
	height => 500,
	linewidth => 2,
	ylabeldelta => 4, # offset of annotations on y axis measured in pixels
	xticknumber => 5, # of tick marks on X axis
	xlabeldelta => 6, # pixels for offset of annotations
	yaxismultiplier => 2.0, # a ratio, used to permit vertical room for peak annotations
	outputformat => 'png',
	x_label => 'm/z',
	y_label => 'Intensity',
	annotationsmatching => \%defaultannotationsmatching,
	colormap => \%defaultcolormap,
);

sub new (\@\@;\@\%\%) # (masses, intensities, [optional] annotations, annotations_matching, colormap)
{
	my $type = shift;
	my $self = {};

	bless $self,$type;

	my($massesRef, $intensitiesRef, $annotationsRef, $annotations_matchingRef, $colormapRef) = @_;

	# Initialise all relevant parameters to defaults
	$self->initialise() or return;

	$self->{masses} = $massesRef;
	$self->{intensities} = $intensitiesRef;
	$self->{annotations} = $annotationsRef;
	$self->{annotationsmatching} = $annotations_matchingRef if $annotations_matchingRef;
	$self->{colormap} = $colormapRef if $colormapRef;

	return $self;
}

sub initialise
{
    my $self = shift;

    foreach (keys %Defaults) 
    {
        $self->set($_, $Defaults{$_});
    }

    return $self;
}


sub set {
        my ($self, $key, $value) = @_;

        $self->{$key} = $value;
}

sub plot
{
	my $self = shift;

	my $minmass;
	my $maxmass;
	my $maxintensity;
	
	my @data_for_graph;
	
	my $i;
	my $j = 0;
	#
	# We are playing a trick by intentionally alternating the real y data values
	# with undefined values (and GD::Graph's skip_undef option), so that GD::Graph
	# doesn't try to plot our actual data ... we need to perform this plotting ourselves.
	# 
	for ($i = 0; $i <= $#{$self->{masses}}; $i++) {
		my $mass = $self->{masses}[$i];
		my $intensity = $self->{intensities}[$i];

		if ($i > 0) {
			$data_for_graph[0][$j] = $mass;
			$data_for_graph[1][$j] = undef;
			$j++;
		}
		$data_for_graph[0][$j] = $mass;
		$data_for_graph[1][$j] = $intensity;
		$minmass = $mass unless defined $minmass and $minmass < $mass;
		$maxmass = $mass unless defined $maxmass and $maxmass > $mass;
		$maxintensity = $intensity unless defined $maxintensity and $maxintensity > $intensity;
		$j++;
	}
	
	#
	# adjust the min and max masses slightly, since otherwise
	# the min and max mass peaks will be obscured by the y axis and the graph's
	# right boundary
	#
	my $massdiff = $maxmass - $minmass;
	$minmass = int($minmass - 0.04 * $massdiff);
	$maxmass = int($maxmass + 0.04 * $massdiff);
	$minmass = 0 if $minmass < 0;
	
	my $graph = GD::Graph::lines->new($self->{width},$self->{height});
	$graph->{graph}->setThickness($self->{linewidth});
	#
	# It turns out that if we don't specify x_tick_number explicitly, it becomes
	# quite messy to compute the conversion of x coordinates and requires the use
	# of lots of undocumented GD::Graph internals
	#
	# We are playing a trick with skip_undef, so that GD::Graph doesn't try to plot
	# our actual data ... we need to perform this plotting ourselves.
	# 
	# We double the maximum intensity so as to leave (hopefully) enough vertical
	# height for peak annotations
	#
	$graph->set(
		x_label             => 'm/z',
		x_label_position    => 0.5,
		skip_undef          => 1,
		x_tick_number       => $self->{xticknumber},
		x_min_value         => $minmass,
		x_max_value         => $maxmass,
		x_number_format     => "%.1f",
		y_min_value         => 0,
		y_max_value         => $maxintensity * $self->{yaxismultiplier},
		y_label => 'Intensity') or die $graph->error;
	
	
	#
	# draw the axes and their labels, and subsequently use the computed geometry
	# for scaling and translating our data points and annotations
	#
	my $im = $graph->plot(\@data_for_graph) or die $graph->error;
	
	my %colors;
	
	# make the background transparent and interlaced
	$colors{'white'} = $im->colorAllocate(255,255,255);
	$im->transparent($colors{'white'});
	$im->interlaced('true');
	
	for ($i = 0; $i <= $#{$self->{masses}}; $i++) {
		my $pattern;
		my $colorname;
		my $match = 'other';
		my $annot = $self->{annotations}[$i];
		my $mass = $self->{masses}[$i];
		my $intensity = $self->{intensities}[$i];
	
		PATTERN:
		foreach $pattern (keys %{$self->{annotationsmatching}}) {
			if ($annot =~ m/$pattern/) {
				$match = $self->{annotationsmatching}{$pattern};
				last PATTERN;
			}
		}
		
		$colorname = $self->{colormap}{$match};
		_init_clr ($im, $colorname, \%colors) or carp "Unable to allocate color $colorname \n";
	#	print "match $match color $colorname \n";
		
		# draw vertical mass peaks and their annotations, if any
		_myline($graph,$im,$mass,0,$mass,$intensity,$colors{$colorname});
		_myannot($graph,$im,$mass,$intensity,$annot,$colors{$colorname},$self->{xlabeldelta},$self->{ylabeldelta});
		
	}
	
	return $im->gif if ($self->{outputformat} eq 'gif');
	return $im->jpeg if ($self->{outputformat} eq 'jpeg');
	return $im->png;
	
}

sub _myline {
	my($graph,$img,$xb,$yb,$xe,$ye,$color) = @_;
	my($xb2,$yb2,$xe2,$ye2);

	($xb2,$yb2) = $graph->val_to_pixel($xb,$yb,1);
	($xe2,$ye2) = $graph->val_to_pixel($xe,$ye,1);
	$img->line($xb2,$yb2,$xe2,$ye2,$color);
	$img->line($xb2,$yb2,$xe2,$ye2,$color);
}

sub _myannot {
	my($graph,$img,$x,$y,$annot,$color,$xlabeldelta,$ylabeldelta) = @_;
	my($x2,$y2) = $graph->val_to_pixel($x,$y,1);

	$img->stringUp(gdLargeFont,$x2-$xlabeldelta,$y2-$ylabeldelta,$annot,$color);
}

# swiped from set_clr in GD::Graph
sub _init_clr ($$\%) {
	my ($gd, $colorname, $colorsRef) = @_;

	my @rgb = _rgb($colorname);
	# All of this could potentially be done by using colorResolve
	# The problem is that colorResolve doesn't return an error
	# condition (-1) if it can't allocate a color. Instead it always
	# returns 0.
	
	# Check if this colour already exists on the canvas
	my $i = $gd->colorExact(@rgb);
	# if not, allocate a new one, and return its index
	$i = $gd->colorAllocate(@rgb) if $i < 0;
	# if this fails, we should use colorClosest.
	$i = $gd->colorClosest(@rgb)  if $i < 0;

	$$colorsRef{$colorname} = $i unless $i < 0;

	return $i;
	
}
1;

__END__

=head1 NAME

MassSpec::ViewSpectrum - Perl extension for viewing a mass spectrum.

=head1 SYNOPSIS

  use MassSpec::ViewSpectrum;

  open PNG, ">mygraphic.png" or die "Unable to open output file\n";
  binmode PNG;

  my @masses = (1036.4,1133,1437,1480,1502);
  my @intensities = (0.1,0.15,0.05,0.10,0.2);
  my @annotations = ('b','w','internal w', '','internal y');

  my $vs = MassSpec::ViewSpectrum->new(\@masses,\@intensities, \@annotations);
  $vs->set(yaxismultiplier => 1.8); # a sample tweak to adjust the output
  my $output = $vs->plot();

  print PNG $output;
  close PNG;

=head1 DESCRIPTION

MassSpec::ViewSpectrum - Perl extension for viewing a mass spectrum, e.g.
typically obtained from the fragmentation of proteins or peptides.

At present this is only implemented using GD graphics, but in principle 
this could be subclassed in the future to include alternative graphic
paradigms such as SVG and Tk.

The current implementation uses a mixture of GD::Graph and native GD, since GD::Graph 1.43 fails to draw the required vertical lines correctly.

=head2 OPTIONS

=over 4

=item width, height

The width and height of the canvas in pixels.
Default: 500 x 500

=item linewidth

Width of vertical spectra in pixels.
Default: 2

=item ylabeldelta

Offset of annotations on y axis measured in pixels.  This is used to permit some whitespace separation between annotations and peaks.
Default: 4

=item xticknumber

Number of tick marks on X axis.
Default: 5

=item xlabeldelta

Number of pixels for offset of annotations on x axis.
Default: 6

=item yaxismultiplier

A ratio, used to permit vertical room for peak annotations.
Default: 2.0

=item outputformat

One of 'png', 'jpg' or 'gif'.  Your local GD installation might only support a subset of these.
Default: 'png'

=item x_label

The label which appears on the X axis.
Default: 'm/z'

=item y_label

The label which appears on the Y axis
Default: 'Intensity'

=back

=head1 SEE ALSO

=head1 AUTHOR

Jonathan Epstein, E<lt>Jonathan_Epstein@nih.govE<gt>

=head1 COPYRIGHT AND LICENSE

                          PUBLIC DOMAIN NOTICE

       National Institute for Child Health and Human Development

 This software/database is a "United States Government Work" under the
 terms of the United States Copyright Act.  It was written as part of
 the author's official duties as a United States Government employee and
 thus cannot be copyrighted.  This software/database is freely available
 to the public for use. The National Institutes of Health and the U.S.
 Government have not placed any restriction on its use or reproduction.

 Although all reasonable efforts have been taken to ensure the accuracy
 and reliability of the software and data, the NIH and the U.S.
 Government do not and cannot warrant the performance or results that
 may be obtained by using this software or data. The NIH and the U.S.
 Government disclaim all warranties, express or implied, including
 warranties of performance, merchantability or fitness for any particular
 purpose.
 
Please cite the author in any work or product based on this material.
 
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.5 or,
at your option, any later version of Perl 5 you may have available.

=cut
