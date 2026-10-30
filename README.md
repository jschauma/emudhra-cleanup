emudhra-cleanup
===============

https://emudhra.we-have-a-problem.com/

In order to remove certificates affected by the
eMudhra compromise, you may need to fiddle with a
number of different CA bundles.

The examples provided on the website above generally
tend to assume that a cert bundle contains comments
annotating the certificates, but that is not always
the case.  If you have bundles that consist entirely
and only of PEM certificates, those commands will not
remove the affected roots.

Instead, you'd have to decode each certificate or
compare the entire PEM blob.  That's tedious.

The `emudhra-cleanup` script is intended to help you
not have to think about that.  It will look for the
roots in a few common places, or let you specify a
given bundle.

Note: in order for the changes to actually be applied,
you need to run the script using `sudo(8)`.  However,
you can of course first run it as a regular user
(possibly with increasing numbers of `-v` flags) to
see what it would do.

Please see the manual page below for more details.

P.S.: 100% human generated.  Don't blame AI, blame me.
(You can blame AI for everything else.)

### Pip and Python

Python's "pip" may use a built-in CA bundle.

You can test whether your specific pip happens to be
vulnerable by running the command below:

```
$ pip download --retries=0 \
        --index-url https://dv-g3b-emudhra.we-have-a-problem.com/ \
        --extra-index-url https://dv-g3b-aaa-emudhra.we-have-a-problem.com/ \
        cowsay
```

This should fail with an error message indicating
`There was a problem confirming the ssl certificate`.
If instead it fails saying `WARNING: Skipping page`,
then pip connected to the remote site, i.e., is
vulnerable.

In that case, you can use `emudhra-cleanup` to fix it
for you via, for example:

```
$ emudhra-cleanup -p /usr/bin/pip3
```

---


```
NAME
     emudhra-cleanup – prune CA bundles from eMudhra related root certificates

SYNOPSIS
     emudhra-cleanup [-Vbhlv] [-d path] [-f file] [-p pip]

DESCRIPTION
     The emudhra-cleanup command attempts to remove eMudhra related root
     certificates from common CA bundles.

OPTIONS
     The following options are supported by emudhra-cleanup:

     -V        Print version number and exit.

     -b        Create a backup file of any modified bundles.

     -d path   Try to detect CA bundles containing the roots located under path,
	       but don't modify them.  Can be specified multiple times.

     -f file   Prune this given file or directory.  Can be specified multiple
	       times.

     -h        Print a short usage statement and exit.

     -l        Enable diagnostic logging.

     -p path   Fix the given pip.  path must be an absolute path to a pip or
	       python executable.

     -v        Be verbose.  Can be specified multiple times to increase
	       verbosity.

DETAILS
     Many of the code examples shown online to update CA bundles to remove the
     root CA certificates affected by the eMudhra compromise assume that a cert
     bundle contains comments annotating the certificates, but that is not
     always the case.  If you have bundles that consist entirely and only of PEM
     certificates, those commands will not remove the affected roots.

     Instead, you'd have to decode each certificate or compare the entire PEM
     blob.  That's tedious.

     emudhra-cleanup is intended to help complete this task.  It will look for
     the roots in a few common places, or let you specify a bundle using the -f
     flag.

     If the -d flag is specified, emudhra-cleanup will either inspect the given
     bundle, or search the given path for likely candidates and output those
     that contain the roots in question.

     Note: the search is done using find(1) with the x flag, meaning you have to
     specify each mount point explicitly.

LOGGING
     If the -l flag is specified, emudhra-cleanup will log diagnostic messages
     using logger(1) with a tag of 'emudhra-cleanup'.

CA BUNDLES
     By default, emudhra-cleanup will look in a few common locations for files
     that are likely to be CA cert bundles.  Specifically, it looks at the
     following:

     /etc/ssl/cert.pem

     /etc/ssl/ca-bundle.pem

     /etc/pki/tls/certs/ca-bundle.crt

     /etc/ssl/certs/ca-certificates.crt

     If the directory '/opt/homebrew' exists, then emudhra-cleanup will also
     consider the files ´/opt/homebrew/etc/*/cert.pem'.

     If the file '/etc/ca-certificates.conf' exists, emudhra-cleanup will add
     exclusion parameters to it and subsequently attempt to run
     update-ca-certificates(8).

     If the -f flag is given, only the specified file(s) will be considered.

ROOTS REMOVED
     emudhra-cleanup removes the following root CA certificates from the CA
     bundles it operates on:

     emSign Root TLS CA - G3
     7DD78D5F4F13459A83DFF9ABBBA62EDBAF6F2D102BF257FD712F4D9F2746ED8D

     emSign Root CS CA - G3
     F2EDAAFF3D9B701FB4D14C9F285F8C0BAD90FC3BCC1FA07D47F4718EDABA34A5

     emSign ECC Root CA - G3
     86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B

     AAA Certificate Services
     D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4

PIP
     Python's "pip" may use a built-in CA bundle.  emudhra-cleanup can try to
     point pip to a fixed CA bundle.  For this, specify the python or pip
     executable via the -p flag.  emudhra-cleanup will update (or create, if it
     does not yet exist) the ´sitecustomize.py' configuration file to set the
     PIP_CERT environment variable.

     If the current process's environment does not have this variable set, then
     emudhra-cleanup will set the value in 'sitecustomize.py' to the file
     /etc/ssl/cert.pem, if it exists.

EXAMPLES
     To verbosely fix the default set of CA bundles, while logging all messages
     and creating backup files of each modified bundle:

	   emudhra-cleanup -b -l -v -v -v -v

     To check, but not modify, all CA bundles under /usr/local:

	   emudhra-cleanup -d /usr/local

     To check, but not modify, specific files:

	   emudhra-cleanup -d /usr/local/etc/cert.pem -d /etc/mycerts.pem

     To update homebrew's pip3.11:

	   emudhra-cleanup -p /opt/homebrew/bin/pip3.11

ENVIRONMENT
     PIP_CERT  The path name to the bundle to use for python/pip.

EXIT STATUS
     The emudhra-cleanup utility exits 0 on success, and >0 if an error occurs.

HISTORY
     emudhra-cleanup was originally written by Jan Schaumann
     ⟨jschauma@netmeister.org⟩ in October 2026.

BUGS
     Please file bugs and feature requests by emailing the author.
```
