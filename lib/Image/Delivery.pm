package Image::Delivery;

=pod

=head1 NAME

Image::Delivery - Efficient transformation and delivery of web images

=head1 INTRODUCTION

Many web applications generate or otherwise deliver graphics as part of their
interface. Getting the delivery of these images right is tricky, and
developers usually need to make trade-offs in order to get a usable mechanism.

Image::Delivery is an extremely sophisticated module for delivering these
generated images. It is designed to be powerful, flexible, extensible,
scalable, secure, stable and correct, and use a minimum of resources.

=head1 DESIGN

Because it can take a little bit of work to set up Image::Delivery, we will
start with a quick once-over of the design of the API, and the reasons and
use cases that drove it.

=head2 Preventing Multiple Server Calls

=head3 Use Case 1: CVS Monitor

  The initial idea for Image::Delivery was due to some problems with
  the design of CVS Monitor (L<http://ali.as/devel/cvsmonitor/), an advanced
  but extremely resource-hungry MVC CGI application. Many of the CVS Monitor
  views have a single large graph on them, which involves a second call to the
  server that starts just before the previous call ends. Generating the graph
  took minimal extra effort, but the overhead of starting another process and
  loading another 100meg of data creates a double whammy hit to the server.
  
  What would be ideal would be to generate both at once and have the browser
  get the image without a CGI hit.

The solution to this problem, and the primary mechanism that Image::Delivery
implements could be called "Static Delivery via Cached Disk", but is best
demonstrated with the diagram outlined in General Structure below.

=head2 Use Case 2: Thumbnails

  One problem with thumbnailing is the vast number that need to be generated.
  When done on demand, if generated by the image request, you will have large
  numbers of processes working. The normal solution is to pre-generate the
  thumbnails, potentially polluting image directories.

Image::Delivery stores all images in one central cache, so that the original
images are unaffected.

=head2 General Structure

    Image Provider
      |
      |BLOB + TransformPath
      |
     \1/
    Image::Delivery
      |           \
      |            |
      |            |
     \2/           |
  Hard Disk        |
  /5\     |        |URI
   |      |        |
   |      |        |
   |     \6/       |
  Web Server       | 
   /4\    |       /
    |     |gzip  /
     \    |     / 
      \  \7/  \3/
      Web Browser

=head3 1) Image Data pulled from Object/Provider

An Object, or a Provider that accesses the data from outside the API,
generates or obtains the image data and various metadata that describes
the image data.

=head3 2) Image Written to File-System

Image::Delivery writes the image to the filesystem with a specific file name

=head3 3) URI sent to Browser in HTML

Image::Delivery determines the matching URI that points to the location of
the written file, and provides it to be used in an C<img> tag in the
generated HTML page.

=head3 4) Web Browser Requests Image

Having received the HTML, the browser requests the image from the web server.

=head3 5) Web Server Finds Image File

The web server receives the image request and finds the file that was
written at step 2)

=head3 6) Web Server Retrieves Image File

Web server reads the file like any other plain file

=head3 7) Web Server Sends File to Browser

Web server sends the file off to the browser

=head2 Digest::TransformPath

Image::Delivery works around source objects. Each source object may want to
work with more than one image, and each image may need to come in several
different versions. In short, there can be lots of variations of images.

To handle this, we utilise (or SHOULD utilise)
L<Digest::TransformPath|Digest::TransformPath> to help identify the images,
with a 10 digit digest built into the filename.

=head2 Might as Well Cache Them

Since we went to all that effort to write the file, its relatively easy to
add caching. But the most important thing if we are going to cache is to
have a good file naming scheme.

=head2 Image::Delivery Naming Scheme

In order to make this all work, the naming scheme is critical.

The basic path format is:

  $ROOT/Object.id/checksum.type

=head3 Object.id

When an object is updated, it may have any number of Image fields, which
may each have any number of scaled/rotated/morphed/derived images. When a
source object is updated, some or all of these need to be cleared.

=head3 checksum

The checksum calculated from the TransformPath does not describe any of the
data, only the data source and modifications to it. This means that it is
possible to cheaply test if the image for a particular transform has already
been created, without having to access any of the data in the actual images.

=head3 type

Because we accept image data in a variety of formats, its not possible to
know what image type any given image should be. So when testing we simply
check the lot until we find one.

Generally, rather than test 10-15 types, the Provider will inform us of the
types to expect. :)

=head2 Operation Profile

All of this junk gives the module the following properties

- Intrinsicaly supports all major image types

- No pre-generation of images, generates everything on-the-fly

- Image names are secure and can't be predicted

- All images for any page are processed in one process hit

- Cache checking is extremely quick

- Never touches image source data when not filling the cache

- Handles many images. Storage extendable to support thousands to millions
of individual images

- Multiple hosts can work with the same Image cache

- Images can be delivered by a different web server to the application

=head1 DESCRIPTION

Image::Delivery is very powerful, but setting it up may take a little bit
of work.

=head2 Setting up the URI <-> path mapping

First, you need to become aquainted with L<HTML::Location|HTML::Location>.
This is used as the basis for the mapping between the disc and a URI.

You should also make sure that whatever process will be running will have
write permissions to the appropriate directory.

For starters, we would suggest creating the cache directory just under the
root of a website, at C<$ROOT/cache>, which will be linked to
C<http://yourwebsite.com/cache/>.

This will let you create your HTML::Location.

  # Set up the location of the cache
  my $Location = HTML::Location->new(
      "$ROOT/cache",
      "http://yourwebsite.com/cache"
      );

This gives you the absolute minimum Image::Delivery itself needs to get
rolling. With a location to manage, you can then start to fire images at it,
and it will store them and hand you back a HTML::Location for the actual
file.

  # Create the Image::Delivery object
  my $Delivery = Image::Delivery->new(
  	Location => $Location,
  	);

However, the tricky bit is probably setting up your Provider class. Although
the abstract class implements much of the details and defaults for you, you
are probably still going to need to do some work to tie the two together.

=head1 STATUS

While the concept and design are fairly well understood and unlikely to
change, there is an unfortunate situation with regards to the Cache::
family of modules.

Although originally written to live at Cache::Web and to be a little more
general, it was felt by the maintainer that Cache::Web would represent the
module as being a full member of the Cache:: family, which it is not.

However, during the first few releases I hope to at least try to move the
API of Image::Delivery as close to Cache:: as possible, possibly under a
common Cache::Interface class, to gain some potential benefits from code
written on top of it.

Until these comments are updated, you should assume that the API may undergo
some changes.

=cut

use 5.005;
use strict;
use UNIVERSAL 'isa', 'can';
use File::Spec                ();
use File::Path                ();
use File::Basename            ();
use File::Remove              ();
use File::Slurp               ();
use List::Util                ();
use Digest::TransformPath     ();
use Image::Delivery::Provider ();

# Add the coercion methods
use Params::Coerce '_Provider'      => 'Image::Delivery::Provider';
use Params::Coerce '_TransformPath' => 'Digest::TransformPath';

use vars qw{$VERSION @FILETYPES};
BEGIN {
	$VERSION   = '0.14';
	@FILETYPES = qw{gif jpg png};
}

=pod

=head1 METHODS

=head2 new %params

The C<new> constructor creates a new Image::Delivery object. It takes
a number of required and optional parameters, provided as a set of
key/value pairs.

=over 4

=item Location

The required Location parameter

=cut

sub new {
	my $class  = ref $_[0] ? ref shift : shift;
	my %params = @_;

	# Check the HTML::Location
	isa(ref $params{Location}, 'HTML::Location') or return undef;
	-d $params{Location}->path and -w _ or return undef;

	# Create the object
	bless { Location => $params{Location} }, $class;
}

=pod

=head2 Location

The C<Location> method returns the L<HTML::Location|HTML::Location>
that was used when creating the Image::Delivery.

=cut

sub Location { $_[0]->{Location} }

=pod

=head2 filename $TransformPath | $Provider

The C<filename> method determines, for a given $TransformPath or $Provider, the
file name that the Image should be written to, excluding the file type.

This is the method most likely to be overloaded, so enable a different
naming scheme.

=cut

sub filename {
	my $self = shift;
	my $Path = $self->_TransformPath($_[0]) or return undef;

	# By default, lets go with digest-first-letter and 10-char digest file
	# e.g. cd3732afc4
	my $digest = $Path->digest(10);
	File::Spec->catfile( substr($digest,0,1), $digest );
}

=pod

=head2 exists $TransformPath | $Provider

For a given Digest::TransformPath, or a ::Provider which contains one, check
to see the a file exists for it in the cache already.

Returns the HTML::Location of the image if it exists, false if it does not
exist, or C<undef> on error.

=cut

sub exists {
	my $self       = shift;
	my $filepath   = $self->filename($_[0]) or return undef;
	my $Provider   = $self->_Provider($_[0]); # Optional
	my @extentions = $Provider ? $Provider->filetypes : @FILETYPES;
	my $filename   = List::Util::first { $self->_exists($_) }
		map { "$filepath.$_" } @extentions
		or return '';
	$self->Location->catfile( $filename );
}

=pod

=head2 get $TransformPath | $Provider

The C<get> methods gets the contents of a cached file from the cache, if it
exists. You should generally check that the image C<exists> first before
trying to get it.

Returns a reference to a SCALAR containing the image data if the image
exists. Returns C<undef> if the image does not exist, or some other error
occurs.

=cut

sub get {
	my $self     = shift;
	my $Location = $self->exists(shift) or return undef;
	File::Slurp::read_file( $Location->path, scalar_ref => 1 ) or undef;
}

=pod

=head2 set $Provider

The C<set> method stores an image in the cache, shortcutting if the image has
already been stored.

Returns the HTML::Location of the stored image on success, or C<undef> on
error.

=cut

sub set {
	my $self     = shift;
	my $Provider = $self->_Provider($_[0]) or return undef;

	# Is it already in the cache
	my $Location = $self->exists($_[0]);
	return undef unless defined $Location; # Pass up error
	return $Location if $Location;         # Already exists

	# Determine where to write the file
	my $file  = $self->filename($_[0]) or return undef;
	my $ext   = $Provider->extension   or return undef;
	$Location = $self->Location->catfile( "$file.$ext" );

	# Get the image data
	my $image = $Provider->image or return undef;

	# Write the image to disk
	my $directory = File::Basename::dirname($Location->path) or return undef;
	eval { File::Path::mkpath($directory) };
	return undef if $@;
	File::Slurp::write_file( $Location->path, $image ) or return undef;

	$Location;
}

=pod

=head2 clear $TransformPath

The C<clear> method allows you to explicitly delete an image from the cache.
This would generally be done for security purposes, as the cache cleaners
will generally harvest files directly, rather than going via TransformPaths.

Returns true if the image was removed, or did not exist. Returns C<undef>
on error.

=cut

sub clear {
	my $self  = shift;
	my $TPath = $self->_TransformPath($_[0]) or return undef;

	# Does the image exist in the cache?
	my $Location = $self->exists($_[0]);
	return undef unless defined $Location;
	return 1 unless $Location; # Already gone

	# Attempt to delete the file
	return undef unless -f $Location->path;
	File::Remove::remove( $Location->path ) ? 1 : undef;
}





#####################################################################
# Support Methods

# Does an image with a particular filename exist?
sub _exists {
	my $self = shift;
	my $filename = defined $_[0] ? shift : return undef;
	-f File::Spec->catfile($self->Location->path, $filename);
}

1;

=pod

=head1 TO DO

- Add ability to mask indexes with empty HTML files

- Add cache clearing capabilities

- Add file locking to prevent race conditions in the cache

- Add pluggable cache cleaners

=head1 SUPPORT

All bugs should be filed via the bug tracker at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Image-Delivery>

For other issues, contact the author

=head1 AUTHORS

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2004 - 2007 Adam Kennedy.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
