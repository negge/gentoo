# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="DJGPP cross-toolchain (i586-pc-msdosdjgpp)"
HOMEPAGE="http://www.delorie.com/djgpp/ https://github.com/andrewwutw/build-djgpp"

CTARGET="i586-pc-msdosdjgpp"

# build-djgpp release tag whose script/${PV} recipe we follow.
BUILD_DJGPP_PV="3.4"

# Versions pinned by script/12.2.0 of build-djgpp v3.4.
BINUTILS_PV="2.30"
DJCRX_PV="2.05"
DJLSR_PV="2.05"
DJDEV_PV="2.05"
AUTOCONF_PV="2.69"
AUTOMAKE_PV="1.15.1"

# DJGPP archive names compress digits: 2.05 -> 205, 2.30 -> 230.
BINUTILS_TAG="${BINUTILS_PV//./}"
DJCRX_TAG="${DJCRX_PV//./}"
DJLSR_TAG="${DJLSR_PV//./}"
DJDEV_TAG="${DJDEV_PV//./}"

DELORIE="https://www.mirrorservice.org/sites/ftp.delorie.com/pub"

SRC_URI="
	https://github.com/andrewwutw/build-djgpp/archive/refs/tags/v${BUILD_DJGPP_PV}.tar.gz
		-> build-djgpp-${BUILD_DJGPP_PV}.tar.gz
	${DELORIE}/djgpp/deleted/v2gnu/bnu${BINUTILS_TAG}s.zip
	${DELORIE}/djgpp/current/v2/djcrx${DJCRX_TAG}.zip
	${DELORIE}/djgpp/current/v2/djlsr${DJLSR_TAG}.zip
	${DELORIE}/djgpp/current/v2/djdev${DJDEV_TAG}.zip
	${DELORIE}/djgpp/rpms/djcross-gcc-${PV}/djcross-gcc-${PV}.tar.bz2
	mirror://gnu/gcc/gcc-${PV}/gcc-${PV}.tar.xz
	mirror://gnu/autoconf/autoconf-${AUTOCONF_PV}.tar.xz
	mirror://gnu/automake/automake-${AUTOMAKE_PV}.tar.xz
"

LICENSE="GPL-2+ GPL-3+ LGPL-2.1+ LGPL-3+ BSD"
SLOT="0"
KEYWORDS="~amd64 ~x86"
IUSE="+cxx"

BDEPEND="
	app-arch/unzip
	sys-devel/bison
	sys-devel/flex
	sys-apps/texinfo
	sys-libs/zlib
	net-misc/curl
	dev-libs/gmp:=
	dev-libs/mpfr:=
	dev-libs/mpc:=
"
RESTRICT="strip test"
QA_PREBUILT="opt/djgpp/*"

PREFIX="/opt/djgpp"

# Don't let portage auto-unpack everything into WORKDIR — build-djgpp's
# script does its own extraction out of a download/ subdir.
S="${WORKDIR}/build-djgpp-${BUILD_DJGPP_PV}"

PATCHES=(
	"${FILESDIR}/build-djgpp-${BUILD_DJGPP_PV}-system-gmp-mpfr-mpc.patch"
)

src_unpack() {
	# Unpack only the build-djgpp recipe tarball; leave the rest as-is
	# in DISTDIR so we can stage them into the script's download/ dir.
	unpack "build-djgpp-${BUILD_DJGPP_PV}.tar.gz"
}

src_prepare() {
	default

	# Stage all distfiles where script/${PV} expects them.
	mkdir -p "${S}/download" || die
	local f
	for f in \
		bnu${BINUTILS_TAG}s.zip \
		djcrx${DJCRX_TAG}.zip \
		djlsr${DJLSR_TAG}.zip \
		djdev${DJDEV_TAG}.zip \
		djcross-gcc-${PV}.tar.bz2 \
		gcc-${PV}.tar.xz \
		autoconf-${AUTOCONF_PV}.tar.xz \
		automake-${AUTOMAKE_PV}.tar.xz \
	; do
		[[ -f ${DISTDIR}/${f} ]] || die "distfile missing: ${f}"
		cp "${DISTDIR}/${f}" "${S}/download/" || die "cp ${f}"
	done

	# Drop our djlsr fix into the script's patch/ dir; the build-djgpp
	# script applies it (via its patched-in `patch -p1` call) right after
	# the upstream patch-djlsr205.txt.
	cp "${FILESDIR}/djlsr-${DJLSR_PV}-gcc15-sortsyms.patch" \
		"${S}/patch/" || die "cp djlsr patch"
}

src_compile() {
	# Stage the entire install under ${T}/stage so we don't escape ${ED}.
	# The script writes binutils first (so gcc can find it), then gcc, etc;
	# everything lands in $DJGPP_PREFIX. After the script finishes we just
	# cp -a the stage tree into the image in src_install.
	#
	# Baked-in --prefix paths reflect the stage dir; gcc/binutils self-locate
	# via make_relative_prefix at runtime, so the post-move binaries find
	# their helpers from argv[0]-relative paths.
	export DJGPP_PREFIX="${T}/stage${PREFIX}"
	export ENABLE_LANGUAGES=$(usex cxx 'c,c++' 'c')
	mkdir -p "${DJGPP_PREFIX}" || die

	# Gentoo exports ABI=amd64 (multilib bookkeeping); some configure
	# scripts choke on it.
	unset ABI MULTILIB_ABIS DEFAULT_ABI

	cd "${S}" || die
	bash "script/${PV}" || die "build-djgpp script failed"
}

src_install() {
	# Move the staged tree into the image (preserves modes/symlinks).
	dodir "${PREFIX%/*}"
	cp -a "${T}/stage${PREFIX}" "${ED}${PREFIX%/*}/" || die

	# env.d: cover both bin dirs — prefixed wrappers + host helpers (stubify, etc.).
	cat > "${T}/99djgpp" <<-EOF
		PATH="${PREFIX}/bin:${PREFIX}/${CTARGET}/bin"
		ROOTPATH="${PREFIX}/bin:${PREFIX}/${CTARGET}/bin"
	EOF
	doenvd "${T}/99djgpp"
}

pkg_postinst() {
	elog ""
	elog "DJGPP cross-toolchain installed under ${PREFIX}"
	elog "Run 'env-update && source /etc/profile', then verify:"
	elog "  ${CTARGET}-gcc --version"
	elog "  stubify -v"
	elog ""
	elog "Ship CWSDPMI.EXE alongside any DOS EXE you produce."
	elog ""
}
