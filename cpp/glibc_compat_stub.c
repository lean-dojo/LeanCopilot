/*
 * Compatibility shim for downstream `lean_exe` targets on Linux.
 *
 * Lean's bundled toolchain ships a hermetic, old glibc build (~2.26) for
 * portability across host distros. When `libleanffi.a` is statically linked
 * into a downstream executable and that executable also links a *system*
 * `libstdc++.so` (see the libstdc++ note in the README), the system
 * libstdc++ may reference glibc entry points that only exist in much newer
 * glibc releases and have no equivalent in Lean's bundled one:
 *
 *   - `__isoc23_strtoul`/`__isoc23_strtoull`/`__isoc23_strtoll`: C23 changed
 *     `strtol`-family semantics (0b binary-prefix support when `base==0`);
 *     glibc >= 2.38 ships these as new, separately-versioned entry points
 *     alongside the classic ones.
 *   - `__libc_single_threaded`: a fast-path hint for `shared_ptr` refcounting,
 *     exposed since glibc >= 2.32.
 *
 * These forwarders satisfy the link when those symbols are otherwise
 * undefined. Because this object is only one member of a static archive, it
 * is pulled into the final link solely when one of these symbols is actually
 * unresolved elsewhere -- it is a no-op whenever the host glibc (or Lean's
 * bundled one) already provides them.
 *
 * Root-caused and originally proposed in
 * https://github.com/lean-dojo/LeanCopilot/issues/196.
 */

#include <stdlib.h>

unsigned long __isoc23_strtoul(const char *nptr, char **endptr, int base) {
  return strtoul(nptr, endptr, base);
}

unsigned long long __isoc23_strtoull(const char *nptr, char **endptr,
                                      int base) {
  return strtoull(nptr, endptr, base);
}

long long __isoc23_strtoll(const char *nptr, char **endptr, int base) {
  return strtoll(nptr, endptr, base);
}

_Bool __libc_single_threaded = 0;
