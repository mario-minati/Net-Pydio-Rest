package Net::Pydio::Rest;

use 5.006;
use strict;
use warnings;

=head1 NAME

Net::Pydio::Rest - Provide access to the Pydio (former ajaxplorer) REST API

=head1 VERSION

Version 0.10

=cut

#<<< NO perltidy - must be all on one line
use version; our $VERSION = version->new('0.10');
#>>>

use Carp qw(confess);
use Data::Dumper;
use Digest::SHA qw(sha1_hex hmac_sha256_hex);
use JSON;
use List::Util qw(any);
use Moose;
use MooseX::Params::Validate;
use REST::Client;
use URI;
use URI::Escape;
use XML::Simple;

has 'rest_client' => (
    is          => 'rw',
    isa         => 'Object',
    required    => 1,
    default     => \&default_rest_client,
);

has 'xml' => (
    is          => 'rw',
    isa         => 'Object',
    required    => 1,
    default     => \&default_xml,
);

has 'debug' => (
    is          => 'rw',
    isa         => 'Bool',
    default     => 0,
);

has 'protocol' => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
    default     => 'http',
);

has 'username' => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
);

has 'password' => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
);

has 'server' => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
);

has 'base_uri' => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
    default     => "/pydio",
);

has 'private' => (
    is          => 'rw',
    isa         => 'Str',
);

has 'token' => (
    is          => 'rw',
    isa         => 'Str',
);


sub BUILD {
    my $self = shift;
    
    # Build URL
    my $strURL = 
        $self->{protocol}.'://'.
        $self->{username}.':'.$self->{password}.'@'.
        $self->{server}.
        $self->{base_uri}.
        '/api/pydio/keystore_generate_auth_token/php_client';
    print "URL: ".$strURL."\n" 
        if $self->{debug};
        
    # Get URL and decode json
    $self->{rest_client}->GET($strURL);
    my $objRestResponse = $self->{rest_client}->responseContent();
    print "Response: ".Dumper($objRestResponse)."\n" 
        if $self->{debug};
    $objRestResponse = from_json($objRestResponse);
    print "Response decoded: ".Dumper($objRestResponse)."\n" 
        if $self->{debug};
        
    $self->{private} = $objRestResponse->{p};
    $self->{token} = $objRestResponse->{t};
}


=head1 SYNOPSIS

    use Net::Pydio::Rest;

    my $pydio = Net::Pydio::Rest->new(
        server => 'pydio.local',
        username => 'admin',
        password => 'secret'
    );
    
    ...

=head1 SUBROUTINES/METHODS

=head2 post

    Send an request to the pydio api via post

=cut

sub post {
    my ( $self, %args ) = validated_hash(
        \@_,
        uri => { isa => 'Str' },
        params => { isa => 'HashRef' },
    );
    
    # Generate random data
    my $strNonce = join "", map { unpack "H*", chr(rand(256)) } 1..3;
    
    # Build authentication hash
    my $message = $self->{base_uri}.$args{uri}.":".$strNonce.":".$self->{private};
    my $messageEncoded = hmac_sha256_hex($message, $self->{token});
    my $authHash = $strNonce.":".$messageEncoded;
    print "Authentication hash: ".$message." --- ".$messageEncoded." --- ".$authHash."\n" 
        if $self->{debug};
    
    # Set api post parameters
    $args{params}->{auth_hash} = $authHash;
    $args{params}->{auth_token} = $self->{token};
    
    # Create rest post data
    my $strRestPostData = substr($self->{rest_client}->buildQuery($args{params}), 1);
    print "RestPostData: ".$strRestPostData."\n" 
        if $self->{debug};

    # Build URL
    my $strURL = 
        $self->{protocol}.'://'.
        $self->{server}.
        $self->{base_uri}.
        $args{uri};
    print "URL: ".$strURL."\n" 
        if $self->{debug};
    
    # Post request
    my $objRestResponse = $self->{rest_client}->POST($strURL, $strRestPostData, {'Content-type' => 'application/x-www-form-urlencoded'});
    print "Response: ".Dumper($objRestResponse)."\n" 
        if $self->{debug};
        
    return $objRestResponse;    
}


=head2 folder_exist

    Check if a given folder exists on the pydio backend

=cut

sub folder_exist {
    my ( $self, %args ) = validated_hash(
        \@_,
        folder => { isa => 'Str' },
        basedir => { isa => 'Str', default => '' },
        workspace => { isa => 'Str', default => 'default' },
        params => { isa => 'HashRef', default => {} },
    );
    
    # Build request path
    my $strPath = "/api/".$args{workspace}."/ls".((length $args{basedir} > 0) ? "/" : "").$args{basedir};
    print "strPath: ".$strPath."\n" 
        if $self->{debug};
    
    # Get directory listing
    my $objRestResponse = $self->post({uri => $strPath, params => $args{params}});
    
    # Test response code
    if ($self->{rest_client}->responseCode() != 200) {
        confess "Unexpected return code " . $self->{rest_client}>responseCode();
    }
    my $objXML = $self->{xml}->XMLin($self->{rest_client}->responseContent());
    print "objXML: ".Dumper($objXML)."\n" 
        if $self->{debug};

    # Extract folder names
    my @foldernames = map {$_->{text}} grep {$_->{ajxp_mime} eq 'ajxp_folder'} @{$objXML->{tree}};
    print "foldernames: ".Dumper(\@foldernames)."\n" 
        if $self->{debug};
        
    # Test if folder exists
    return 1
        if any { $_ eq $args{folder}} @foldernames;
        
    return 0;
}


=head2 folder_create

    Create a new folder on the pydio backend

=cut

sub folder_create {
    my ( $self, %args ) = validated_hash(
        \@_,
        folder => { isa => 'Str' },
        basedir => { isa => 'Str', default => '/' },
        workspace => { isa => 'Str', default => 'default' },
        params => { isa => 'HashRef', default => {} },
    );
    
    # Build request path
    my $strPath = "/api/".$args{workspace}."/mkdir";
    print "strPath: ".$strPath."\n" 
        if $self->{debug};
    
    # Create new directory
    $args{params}->{dir} = $args{basedir};
    $args{params}->{dirname} = $args{folder};
    my $objRestResponse = $self->post({uri => $strPath, params => $args{params}});
    
    # Test response code
    if ($self->{rest_client}->responseCode() != 200) {
        confess "Unexpected return code " . $self->{rest_client}->responseCode();
    }
    my $objXML = $self->{xml}->XMLin($self->{rest_client}->responseContent());
    print "objXML: ".Dumper($objXML)."\n" 
        if $self->{debug};
    if (defined $objXML->{nodes_diff}) {
        print "Succesfully created folder.\n" 
            if $self->{debug};
        return 1;
    }
    print "Could not create folder.\n" 
        if $self->{debug};
    return 0;
}


=head2 folder_share_as_repository

    Share a given folder as repository.
    
=cut

sub folder_share_as_repository {
    my ( $self, %args ) = validated_hash(
        \@_,
        folder => { isa => 'Str' },
        basedir => { isa => 'Str', default => '/' },
        workspace => { isa => 'Str', default => 'default' },
        repository => { isa => 'Str', option => 1 },
        users => { isa => 'HashRef', default => {} },
        params => { isa => 'HashRef', default => {} },
    );
    $args{repository} ||= $args{folder};
    
    # Build request path
    my $strPath = "/api/".$args{workspace}."/share/public".$args{basedir}.$args{folder};
    print "strPath: ".$strPath."\n" 
        if $self->{debug};
        
    # Build post parameters
    $args{params}->{sub_action} = 'delegate_repo';
    $args{params}->{repo_label} = $args{repository};
    my $intUserIdx = 0;
    foreach my $strUser (keys %{$args{users}}) {
        print "strUser: ".$strUser."\n" 
            if $self->{debug};
        $args{params}->{'user_'.$intUserIdx} = uri_escape($strUser);
        $args{params}->{'entry_type_'.$intUserIdx} = 'user';
        $args{params}->{'right_read_'.$intUserIdx} = (index($args{users}->{$strUser}, 'r') >= 0) ? 'true' : 'false';
        $args{params}->{'right_write_'.$intUserIdx} = (index($args{users}->{$strUser}, 'w') >= 0) ? 'true' : 'false';
        $args{params}->{'right_watch_'.$intUserIdx} = (index($args{users}->{$strUser}, 'W') >= 0) ? 'true' : 'false';
        $intUserIdx++;
    }
    print "$args{params}: ".Dumper($args{params})."\n" 
        if $self->{debug};
    
    # Create share
    my $objRestResponse = $self->post({uri => $strPath, params => $args{params}});
    
    # Test response code
    if ($self->{rest_client}->responseCode() != 200) {
        confess "Unexpected return code " . $self->{rest_client}->responseCode();
    }
    
    # There is no clue in the response to discover if the request was successfull.
}


=head2 get_shared_repository_data

    Get the JSON data of a given shared repository.
    
=cut

sub get_shared_repository_data {
    my ( $self, %args ) = validated_hash(
        \@_,
        folder => { isa => 'Str' },
        basedir => { isa => 'Str', default => '/' },
        workspace => { isa => 'Str', default => 'default' },
        params => { isa => 'HashRef', default => {} },
    );
    
    # Build request path
    my $strPath = "/api/".$args{workspace}."/load_shared_element_data".$args{basedir}.$args{folder};
    print "strPath: ".$strPath."\n" 
        if $self->{debug};
        
    # Build post parameters
    $args{params}->{'element-type'} = 'repository';
    
    # Load data
    my $objRestResponse = $self->post({uri => $strPath, params => $args{params}});
    
    # Test response code
    if ($self->{rest_client}->responseCode() != 200) {
        confess "Unexpected return code " . $self->{rest_client}->responseCode();
    }
    unless (length $self->{rest_client}->responseContent() > 0) {
        confess "Missing content";
    }
    
    # Import content
    my $objData = from_json($self->{rest_client}->responseContent());
    print "objData: ".Dumper($objData)."\n" 
        if $self->{debug};
    
    return $objData;
}


=head2 user_create

    Create a new user.
    
=cut

sub user_create {
    my ( $self, %args ) = validated_hash(
        \@_,
        login => { isa => 'Str' },
        password => { isa => 'Str' },
        params => { isa => 'HashRef', default => {} },
    );
    
    # Build request path
    my $strPath = "/api/ajxp_conf/create_user/".uri_escape($args{login})."/".uri_escape($args{password});
    print "strPath: ".$strPath."\n" 
        if $self->{debug};
    
    # Create new user
    my $objRestResponse = $self->post({uri => $strPath, params => $args{params}});
    
    # Test response code
    if ($self->{rest_client}->responseCode() != 200) {
        confess "Unexpected return code " . $self->{rest_client}->responseCode();
    }
    my $objXML = $self->{xml}->XMLin($self->{rest_client}->responseContent());
    print "objXML: ".Dumper($objXML)."\n" 
        if $self->{debug};
    if (defined $objXML->{message} && 
        defined $objXML->{message}->{type} &&
        $objXML->{message}->{type} eq 'SUCCESS') {
        print "Succesfully created user.\n" 
            if $self->{debug};
        return 1;
    }
    print "Could not create user.\n" 
        if $self->{debug};
    return 0;
}


=head2 user_list

    Get list of all users.
    Primary admin user is not part of list.
    
=cut

sub user_list {
    my ( $self, %args ) = validated_hash(
        \@_,
        params => { isa => 'HashRef', default => {} },
    );
    
    # Build request path
    my $strPath = "/api/ajxp_conf/ls/data/users";
    print "strPath: ".$strPath."\n" 
        if $self->{debug};
    
    # Send request
    my $objRestResponse = $self->post({uri => $strPath, params => $args{params}});
    
    # Test response code
    if ($self->{rest_client}->responseCode() != 200) {
        confess "Unexpected return code " . $self->{rest_client}->responseCode();
    }
    my $objXML = $self->{xml}->XMLin($self->{rest_client}->responseContent());
    print "objXML: ".Dumper($objXML)."\n" 
        if $self->{debug};
        
    # Extract user names
    my @usernames = map {$_->{object_id}} grep {$_->{ajxp_mime} eq 'user_editable'} @{$objXML->{tree}};
    
    return \@usernames;
}


=head2 default_rest_client

    Create the rest client object which is used to access the pydio rest server.
    
=cut

sub default_rest_client {
    return REST::Client->new();
}

=head2 default_xml

    Create the xml object which is used to decode answers from rest server.
    
=cut

sub default_xml {
    return XML::Simple->new();
}

=head1 AUTHOR

Mario Minati, C<< <cpan at minati.de> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-net-pydio-rest at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-Pydio-Rest>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::Pydio::Rest


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-Pydio-Rest>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-Pydio-Rest>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-Pydio-Rest>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-Pydio-Rest/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2015 Mario Minati.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.


=cut

1; # End of Net::Pydio::Rest
