#!/usr/bin/perl
# otrs-update-setting.pl

use strict;
use warnings;

use lib qw(/opt/otrs /opt/otrs/Kernel/cpan-lib);

use Getopt::Long;
use Pod::Usage;
use feature qw/switch/;

use Kernel::System::ObjectManager;

# create common objects
local $Kernel::OM = Kernel::System::ObjectManager->new();
my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');

my @AvailableActions = (
    "disable",
    "enable",
    "string-mod-item",
    "textarea-mod-item",
    "option-mod-item",
    "array-add-element",
    "array-del-element",
    "hash-add-key-value",
    "hash-del-key",
    "hash-mod-key-value",
    "hash-mod-key-subarray-add-element",
    "hash-mod-key-subarray-del-element",
    "hash-mod-key-subhash-add-key-value",
    "hash-mod-key-subhash-del-key-value",
    "hash-mod-key-subhash-mod-key-value",
);

my ( $help, $key, $options, $subkey, $value, $rewrite );

GetOptions(
    "help"     => \$help,
    "key=s"    => \$key,
    "options"  => \$options,
    "subkey=s" => \$subkey,
    "value=s"  => \$value,
    "rewrite"  => \$rewrite,
) or pod2usage( { -message => "ERROR: Invalid Parameter" } );

my $ItemName = $ARGV[0];
my $Action = $ARGV[1];

if ($help) {
    pod2usage(
        {
            -message    => qq(Use "otrs-update-setting.pl -options" to see a detailed description of the parameters),
            -exitstatus => 0,
            -verbose    => 0,
        }
    );
}

if ($options) {
    pod2usage( { -exitstatus => 0 } );
}

my %ItemHash;

if ( not $ItemName ) {
    pod2usage( { -message => "ERROR: A configuration item has not be specified" } );
}
else {
    %ItemHash = $SysConfigObject->ConfigItemGet(
        Name => $ItemName,
    );
    if ( ! %ItemHash ) {
        pod2usage( { -message => "ERROR: Invalid configuration item" } );
    }
}

if ( not $Action ) {
    pod2usage( { -message => "ERROR: An action has not been given" } );
}
else {
    # check if valid action
    # for reference: https://perlmaven.com/filtering-values-with-perl-grep
    if ( ! grep $Action eq $_, @AvailableActions ) {
        pod2usage( { -message => "ERROR: Invalid action" } );
    }
}

sub print_info {
    print "\e[42m[INFO]\e[0m $_[0]\n"
}

sub print_error {
    print "\e[101m[ERROR]\e[0m $_[0]\n"
}

sub print_warning {
    print "\e[43m[WARNING]\e[0m $_[0]\n"
}

sub GetContent {
    my $Content;

    if ( defined $ItemHash{Setting}->[1]->{String} ) {
        $Content = $ItemHash{Setting}->[1]->{String}->[1]->{Content};
    }
    elsif ( defined $ItemHash{Setting}->[1]->{TextArea} ) {
        $Content = $ItemHash{Setting}->[1]->{TextArea}->[1]->{Content};
    }
    elsif ( defined $ItemHash{Setting}->[1]->{Option} ) {
        $Content = $ItemHash{Setting}->[1]->{Option}->[1]->{SelectedID};
    }
    elsif ( defined $ItemHash{Setting}->[1]->{Hash} ) {
        my %ContentHash;
        my @items = @{$ItemHash{Setting}->[1]->{Hash}->[1]->{Item}};
        for my $i ( 1 .. $#items ) {
            if ( defined $items[$i]->{Array} ) {
                my @ContentSubArray;
                
                for my $j ( 1 .. $#{$items[$i]->{Array}->[1]->{Item}} ) {
                    push(@ContentSubArray, $items[$i]->{Array}->[1]->{Item}->[$j]->{Content});
                }
                $ContentHash{$items[$i]->{Key}} = \@ContentSubArray;
            }
            elsif ( defined $items[$i]->{Hash} ) {
                my %ContentSubHash;
                
                for my $j ( 1 .. $#{$items[$i]->{Hash}->[1]->{Item}} ) {
                    $ContentSubHash{$items[$i]->{Hash}->[1]->{Item}->[$j]->{Key}} = $items[$i]->{Hash}->[1]->{Item}->[$j]->{Content};
                }
                $ContentHash{$items[$i]->{Key}} = \%ContentSubHash;
            }
            else {
                $ContentHash{$items[$i]->{Key}} = $items[$i]->{Content};
            }
        }
        $Content = \%ContentHash;
    }
    elsif ( defined $ItemHash{Setting}->[1]->{Array} ) {
        my @ContentArray;
        my @items = @{$ItemHash{Setting}->[1]->{Array}->[1]->{Item}};
        for my $i ( 1 .. $#items ) {
            push(@ContentArray, $items[$i]->{Content});
        }
        $Content = \@ContentArray;
    }

    return $Content;
}

my $Result;

if    ( $Action =~ /^disable$/ ) {
    if ( $ItemHash{Required} && $ItemHash{Required} == 1 ) {
        $Result = 0;
        print_error "Cannot disable required configuration item";
    }
    else {
        $Result = $SysConfigObject->ConfigItemUpdate(
            Key   => $ItemName,
            Value => GetContent,
            Valid => 0,
        );

        if ( ! $Result ) {
            print_error( qq(Unable to disable configuration item "$ItemName") );
        } else {
            print_info( qq("$ItemName" has been disabled) );
            $SysConfigObject->CreateConfig() if ( $rewrite );
        }
    }
}
elsif ( $Action =~ /^enable$/ ) {
    $Result = $SysConfigObject->ConfigItemUpdate(
        Key   => $ItemName,
        Value => GetContent,
        Valid => 1,
    );

    if ( ! $Result ) {
        print_error( qq(Unable to enable configuration item "$ItemName") );
    } else {
        print_info( qq("$ItemName" has been enabled) );
        $SysConfigObject->CreateConfig() if ( $rewrite );
    }
}
elsif ( $ItemHash{ReadOnly} ) {
    $Result = 0;
    print_error( qq("$ItemName" is read only) );
}
else {
    my $Content;

    if ( $Action =~ /^(string-mod-item|textarea-mod-item|option-mod-item)$/ ) {
        if ( defined $value ) {
            $Content = $value;
        }
        else {
            pod2usage( { -message => "ERROR: No value specified" } );
        }
    }
    elsif ( $Action =~ /^array-add-element$/ ) {
        my $ContentArrayRef = GetContent;
        my @ContentArray = @$ContentArrayRef;

        if ( defined $value ) {
            if ( grep $value eq $_, @ContentArray ) {
                print_error( qq("$ItemName" already contains specified value) );
                exit 1;
            }
            else {
                push(@ContentArray, $value);
                $Content = \@ContentArray;
            }
        }
        else {
            pod2usage( { -message => "ERROR: No value specified" } );
        }
    }
    elsif ( $Action =~ /^array-del-element$/ ) {
        my $ContentArrayRef = GetContent;
        my @ContentArray = @$ContentArrayRef;

        if ( defined $value ) {
            if ( grep $value eq $_, @ContentArray ) {
                @ContentArray = grep { $_ ne $value } @ContentArray;
                $Content = \@ContentArray;
            }
            else {
                print_error( qq("$ItemName" does not contain the specified value) );
                exit 1;
            }
        }
        else {
            pod2usage( { -message => "ERROR: No value specified" } );
        }
    }
    elsif ( $Action =~ /^hash-add-key-value$/ ) {
        my $ContentHashRef = GetContent;
        my %ContentHash = %$ContentHashRef;
        
        if ( ! defined $key ) {
            pod2usage( { -message => "ERROR: Hash key not specified" } );
        }
        
        if ( ! defined $value ) {
            pod2usage( { -message => "ERROR: No value specified" } );
        }
        
        if ( exists( $ContentHash{$key} ) ) {
            print_error( qq("$ItemName" already contains the specified key) );
            exit 1;
        }
        else {
            $ContentHash{$key} = $value;
            $Content = \%ContentHash;
        }
    }
    elsif ( $Action =~ /^hash-del-key$/ ) {
        my $ContentHashRef = GetContent;
        my %ContentHash = %$ContentHashRef;
        
        if ( ! defined $key ) {
            pod2usage( { -message => "ERROR: Hash key not specified" } );
        }
        
        if ( exists( $ContentHash{$key} ) ) {
            delete $ContentHash{$key};
            $Content = \%ContentHash;
        }
        else {
            print_error( qq("$ItemName" does not contain the specified key) );
            exit 1;
        }
    }
    elsif ( $Action =~ /^hash-mod-key-value$/ ) {
        my $ContentHashRef = GetContent;
        my %ContentHash = %$ContentHashRef;
        
        if ( ! defined $key ) {
            pod2usage( { -message => "ERROR: Hash key not specified" } );
        }
        
        if ( ! defined $value ) {
            pod2usage( { -message => "ERROR: No value specified" } );
        }
        
        if ( exists( $ContentHash{$key} ) ) {
            $ContentHash{$key} = $value;
            $Content = \%ContentHash;
        }
        else {
            print_error( qq("$ItemName" does not contain the specified key) );
            exit 1;
        }
    }
    elsif ( $Action =~ /^hash-mod-key-subarray-add-element$/ ) {
        my $ContentHashRef = GetContent;
        my %ContentHash = %$ContentHashRef;
        
        if ( ! defined $key ) {
            pod2usage( { -message => "ERROR: Hash key not specified" } );
        }
        
        if ( ! defined $value ) {
            pod2usage( { -message => "ERROR: No value specified" } );
        }
        
        if ( exists( $ContentHash{$key} ) ) {
            if ( ref($ContentHash{$key}) eq 'ARRAY' ) {
                my @ContentSubArray = @{$ContentHash{$key}};

                if ( grep $value eq $_, @ContentSubArray ) {
                    print_error( qq(The array in hash key "$key" of "$ItemName" already contains specified value) );
                    exit 1;
                }
                else {
                    push(@ContentSubArray, $value);
                    $ContentHash{$key} = \@ContentSubArray;
                }

                $Content = \%ContentHash;
            }
            else {
                print_error( qq(The hash key "$key" of "$ItemName" does not contain an array) );
                exit 1;
            }
        }
        else {
            print_error( qq("$ItemName" does not contain the specified key) );
            exit 1;
        }
    }
    elsif ( $Action =~ /^hash-mod-key-subarray-del-element$/ ) {
        my $ContentHashRef = GetContent;
        my %ContentHash = %$ContentHashRef;
        
        if ( ! defined $key ) {
            pod2usage( { -message => "ERROR: Hash key not specified" } );
        }
        
        if ( ! defined $value ) {
            pod2usage( { -message => "ERROR: No value specified" } );
        }
        
        if ( exists( $ContentHash{$key} ) ) {
            if ( ref($ContentHash{$key}) eq 'ARRAY' ) {
                my @ContentSubArray = @{$ContentHash{$key}};

                if ( grep $value eq $_, @ContentSubArray ) {
                    @ContentSubArray = grep { $_ ne $value } @ContentSubArray;
                    $ContentHash{$key} = \@ContentSubArray;
                }
                else {
                    print_error( qq(The array in hash key "$key" of "$ItemName" does not contain the specified value) );
                    exit 1;
                }

                $Content = \%ContentHash;
            }
            else {
                print_error( qq(The hash key "$key" of "$ItemName" does not contain an array) );
                exit 1;
            }
        }
        else {
            print_error( qq("$ItemName" does not contain the specified key) );
            exit 1;
        }
    }
    elsif ( $Action =~ /^hash-mod-key-subhash-add-key-value$/ ) {
        my $ContentHashRef = GetContent;
        my %ContentHash = %$ContentHashRef;
        
        if ( ! defined $key ) {
            pod2usage( { -message => "ERROR: Hash key not specified" } );
        }
        
        if ( ! defined $subkey ) {
            pod2usage( { -message => "ERROR: Sub Hash key not specified" } );
        }
        
        if ( ! defined $value ) {
            pod2usage( { -message => "ERROR: No value specified" } );
        }
        
        if ( exists( $ContentHash{$key} ) ) {
            if ( ref($ContentHash{$key}) eq 'HASH' ) {
                my %ContentSubHash = %{$ContentHash{$key}};

                if ( exists( $ContentSubHash{$subkey} ) ) {
                    print_error( qq(The hash in hash key "$key" of "$ItemName" already contains the specified key) );
                    exit 1;
                }
                else {
                    $ContentSubHash{$subkey} = $value;
                    $ContentHash{$key} = \%ContentSubHash;
                }

                $Content = \%ContentHash;
            }
            else {
                print_error( qq(The hash key "$key" of "$ItemName" does not contain a hash) );
                exit 1;
            }
        }
        else {
            print_error( qq("$ItemName" does not contain the specified key) );
            exit 1;
        }
    }
    elsif ( $Action =~ /^hash-mod-key-subhash-del-key-value$/ ) {
        my $ContentHashRef = GetContent;
        my %ContentHash = %$ContentHashRef;
        
        if ( ! defined $key ) {
            pod2usage( { -message => "ERROR: Hash key not specified" } );
        }
        
        if ( ! defined $subkey ) {
            pod2usage( { -message => "ERROR: Sub Hash key not specified" } );
        }
        
        if ( exists( $ContentHash{$key} ) ) {
            if ( ref($ContentHash{$key}) eq 'HASH' ) {
                my %ContentSubHash = %{$ContentHash{$key}};

                if ( exists( $ContentSubHash{$subkey} ) ) {
                    delete $ContentSubHash{$subkey};
                    $ContentHash{$key} = \%ContentSubHash;
                }
                else {
                    print_error( qq(The hash in hash key "$key" of "$ItemName" does not contain the specified key) );
                    exit 1;
                }

                $Content = \%ContentHash;
            }
            else {
                print_error( qq(The hash key "$key" of "$ItemName" does not contain a hash) );
                exit 1;
            }
        }
        else {
            print_error( qq("$ItemName" does not contain the specified key) );
            exit 1;
        }
    }
    elsif ( $Action =~ /^hash-mod-key-subhash-mod-key-value$/ ) {
        my $ContentHashRef = GetContent;
        my %ContentHash = %$ContentHashRef;
        
        if ( ! defined $key ) {
            pod2usage( { -message => "ERROR: Hash key not specified" } );
        }
        
        if ( ! defined $subkey ) {
            pod2usage( { -message => "ERROR: Sub Hash key not specified" } );
        }
        
        if ( ! defined $value ) {
            pod2usage( { -message => "ERROR: No value specified" } );
        }
        
        if ( exists( $ContentHash{$key} ) ) {
            if ( ref($ContentHash{$key}) eq 'HASH' ) {
                my %ContentSubHash = %{$ContentHash{$key}};

                if ( exists( $ContentSubHash{$subkey} ) ) {
                    $ContentSubHash{$subkey} = $value;
                    $ContentHash{$key} = \%ContentSubHash;
                }
                else {
                    print_error( qq(The hash in hash key "$key" of "$ItemName" does not contain the specified key) );
                    exit 1;
                }

                $Content = \%ContentHash;
            }
            else {
                print_error( qq(The hash key "$key" of "$ItemName" does not contain a hash) );
                exit 1;
            }
        }
        else {
            print_error( qq("$ItemName" does not contain the specified key) );
            exit 1;
        }
    }

    # validate the value
    my $ValidateOk = $SysConfigObject->ConfigItemValidate(
        Key   => $ItemName,
        Value => $Content,
    );

    if ( ! $ValidateOk ) {
        $Result = 0;
        print_error "Invalid value specified";
    }
    else {
        $Result = $SysConfigObject->ConfigItemUpdate(
            Key          => $ItemName,
            Value        => $Content,
            Valid        => 1,
            NoValidation => 1,
        );

        if ( ! $Result ) {
            print_error( qq(Unable to modify "$ItemName") );
        } else {
            print_info( qq("$ItemName" was modified successfully) );
            $SysConfigObject->CreateConfig() if ( $rewrite );
        }
    }
}

exit !$Result;

=pod

=head1 NAME

otrs-update-setting.pl

=head1 SYNOPSIS

    otrs-update-setting.pl <name> <action> [-key <key> [-subkey <subkey>]] [-value <value>] [-rewrite]
or
    otrs-update-setting.pl -help
or
    otrs-update-setting.pl -options


=head1 DESCRIPTION

This script will perform the requested action to update an OTRS config item.

=head1 OPTIONS

=over

=item I<< <name> >>

B<REQUIRED>: The name of the configuration item to be updated.

=item I<< <action> >>

B<REQUIRED>: The action to be performed on the configuration item.

=over

=item B<Available Actions>:

=over

=item disable

Disables the configuration item.

=item enable

Enables the configuration item.

=item string-mod-item

Update configuration item with content of type String.
Use with -value option.

=item textarea-mod-item

Update configuration item with content of type TextArea.
Use with -value option.

=item option-mod-item

Update configuration item with content of type Option.
Use with -value option.

=item array-add-element

Add element to configuration item with content of type Array.
Use with -value option.

=item array-del-element

Delete element from configuration item with content of type Array.
Use with -value option.

=item hash-add-key-value

Add key/value to configuration item with content of type Hash.
Use with -key and -value options.

=item hash-del-key

Delete key from configuration item with content of type Hash.
Use with -key option.

=item hash-mod-key-value

Update key value for configuration item with content type Hash.
Use with -key and -value options.

=item hash-mod-key-subarray-add-element

Add element to configuration item with content of type Sub-Array.
Use with -key and -value options.

=item hash-mod-key-subarray-del-element

Delete element from configuration item with content of type Sub-Array.
Use with -key and -value options.

=item hash-mod-key-subhash-add-key-value

Add key/value to configuration item with content of type Sub-Hash.
Use with -key, -subkey and -value options.

=item hash-mod-key-subhash-del-key-value

Delete key from configuration item with content of type Sub-Hash.
Use with -key and -subkey options.

=item hash-mod-key-subhash-mod-key-value

Update key value for configuration item with content of type Sub-Hash.
Use with -key, -subkey and -value options.

=back

=item -key:

Hash key.

=item -subkey:

Sub-Hash key.

=item -value:

New value.

=item -rewrite

Rewrites system configuration file with current settings.

=item -help

Displays a brief help message just showing the command line options.

=item -options

Displays indepth help message showing the command line and description
of all the options.

=back

=back

=cut
