# copied from now license_finder, but it forgot to return the text
def crunch_license_ret_text(licfile):
    '''
    Remove non-material text from a license file and then calculate its
    md5sum. This works well for licenses that contain a copyright statement,
    but is also a useful way to handle people's insistence upon reformatting
    the license text slightly (with no material difference to the text of the
    license).
    '''

    import oe.utils, re, hashlib

    # Note: these are carefully constructed!
    license_title_re = re.compile(r'^#*\(? *(This is )?([Tt]he )?.{0,15} ?[Ll]icen[sc]e( \(.{1,10}\))?\)?[:\.]? ?#*$')
    license_statement_re = re.compile(r'^((This (project|software)|.{1,10}) is( free software)? (released|licen[sc]ed)|(Released|Licen[cs]ed)) under the .{1,10} [Ll]icen[sc]e:?$')
    copyright_re = re.compile(r'^ *[#\*]* *(Modified work |MIT LICENSED )?Copyright ?(\([cC]\))? .*$')
    disclaimer_re = re.compile(r'^ *\*? ?All [Rr]ights [Rr]eserved\.$')
    email_re = re.compile(r'^.*<[\w\.-]*@[\w\.\-]*>$')
    header_re = re.compile(r'^(\/\**!?)? ?[\-=\*]* ?(\*\/)?$')
    tag_re = re.compile(r'^ *@?\(?([Ll]icense|MIT)\)?$')
    url_re = re.compile(r'^ *[#\*]* *https?:\/\/[\w\.\/\-]+$')

    lictext = []
    with open(licfile, 'r', errors='surrogateescape') as f:
        for line in f:
            # Drop opening statements
            if copyright_re.match(line):
                continue
            elif disclaimer_re.match(line):
                continue
            elif email_re.match(line):
                continue
            elif header_re.match(line):
                continue
            elif tag_re.match(line):
                continue
            elif url_re.match(line):
                continue
            elif license_title_re.match(line):
                continue
            elif license_statement_re.match(line):
                continue
            # Strip comment symbols
            line = line.replace('*', '') \
                       .replace('#', '')
            # Unify spelling
            line = line.replace('sub-license', 'sublicense')
            # Squash spaces
            line = oe.utils.squashspaces(line.strip())
            # Replace smart quotes, double quotes and backticks with single quotes
            line = line.replace(u"\u2018", "'").replace(u"\u2019", "'").replace(u"\u201c","'").replace(u"\u201d", "'").replace('"', '\'').replace('`', '\'')
            # Unify brackets
            line = line.replace("{", "[").replace("}", "]")
            if line:
                lictext.append(line)

    m = hashlib.md5()
    try:
        text = ' '.join(lictext)
        m.update(text.encode('utf-8'))
        md5val = m.hexdigest()
    except UnicodeEncodeError:
        text = ""
        md5val = None
    return md5val, text

def unescape_path(path):
    import re
    """Unescape capital letters using exclamation points."""
    return re.sub(r'!([a-z])', lambda m: m.group(1).upper(), path)

# lets stick to LICENSE files for now, scanning all files requires even more hashes.
def get_license_file(dir):
    licfile = os.path.join(dir, "LICENSE")
    if os.path.exists(licfile):
        return licfile
    licfile = os.path.join(dir, "LICENSE.md")
    if os.path.exists(licfile):
        return licfile
    licfile = os.path.join(dir, "LICENSE.txt")
    if os.path.exists(licfile):
        return licfile
    return None


def update_modules_src_uris(d):
    import glob

    dldir = d.expand("${GOMODCACHE}/cache/download", d)
    bb.warn(dldir)
    dependencies = sorted(glob.glob("**/*.zip", root_dir=dldir, recursive=True))
    modules = []

    modsfile = bb.data.expand("${THISDIR}/${BPN}-go-mods.inc", d)
    with open(modsfile + ".tmp", "w") as f:
        f.write('SRC_URI += " \\\n')

        for dep in dependencies:
            parts = dep.split("/@v/")
            if len(parts) != 2:
                bb.fatal("go urls should have @v")

            url = unescape_path(parts[0])
            version = parts[1].removesuffix(".zip")

            mod = url + "@" + version
            modules.append(mod)

            sha256 = bb.utils.sha256_file(os.path.join(dldir, dep))
            f.write(f"    gomod://{url};version={version};sha256sum={sha256} \\\n")

        f.write('"\n')

    # check if there are mod files without zip files, there is something with mod=1..
    modfiles = sorted(glob.glob("**/*.mod", root_dir=dldir, recursive=True))
    for mod in sorted(modfiles):
        zip = mod.removesuffix(".mod") + ".zip"
        if (not zip in  dependencies):
            bb.warn(f"{mod} is not in the zip list")

    os.rename(modsfile + ".tmp", modsfile)

    return modules


def update_license_files(d, modules):
    import glob, urllib
    from oe.license import tidy_licenses
    from oe.license_finder import _load_hash_csv, _crunch_license, _crunch_known_licenses
    from oe.utils import read_file

    md5sums = {}
    md5sums.update(_load_hash_csv(d))
    md5sums.update(_crunch_known_licenses(d))

    licdir = d.getVar("GOMODCACHE")
    licenses = []

    licgen =  bb.data.expand("${THISDIR}/${BPN}-licenses.inc", d)
    with open(licgen + ".tmp", "w") as f:
        f.write('LIC_FILES_CHKSUM += " \\\n')

        for module in modules:
            licfile = get_license_file(os.path.join(licdir, module))
            if licfile is None:
                bb.error(f"no license found for {module}")
                continue

            crunched_md5, curnched_text = crunch_license_ret_text(licfile)
            md5 = bb.utils.md5_file(licfile)

            if crunched_md5 in md5sums:
                license_name = md5sums[crunched_md5]
                bb.warn("crunched license is " + license_name)
            elif md5 in md5sums:
                license_name = md5sums[md5]
                bb.warn("license is " + license_name)
            else:
                license_name = "Unknown"
                bb.error(f"license not found: md5: {md5} crunched: {crunched_md5}")
                bb.warn(oe.utils.read_file(licfile))
                bb.warn(curnched_text)

            spdx_encoded = urllib.parse.quote_plus(license_name)
            licenses.append(license_name)
            relpath = os.path.relpath(licfile, licdir)
            f.write(f"    file://pkg/mod/{relpath};md5={md5};spdx={spdx_encoded} \\\n")

        f.write('"\n\n')
        all_licenses = " & ".join(tidy_licenses(licenses))
        bb.warn(all_licenses)
        f.write(f'LICENSE += " & {all_licenses}"\n')

    os.rename(licgen + ".tmp", licgen)

repopulate_cache() {
	# populate the cache with what is needed for do_compile
	${GO} clean -modcache
	go_do_compile
}

addtask do_update_modules_prune after do_configure
do_update_modules_prune[nostamp] = "1"
do_update_modules_prune[network] = "1"
do_update_modules_prune[dirs] = "${GOTMPDIR} ${B}/src/${GO_WORKDIR}"
do_update_modules_prune[cleandirs] = "${GOMODCACHE}"

python do_update_modules_prune() {
    keys = sorted(d.getVarFlags('PACKAGECONFIG').keys())
    allconfigs = ' '.join(keys)
    d.setVar('PACKAGECONFIG', allconfigs)
    bb.warn(f"setting PACKAGECONFIG to {allconfigs}")

    bb.build.exec_func("repopulate_cache", d)
    modules = update_modules_src_uris(d)
    update_license_files(d, modules)
}
