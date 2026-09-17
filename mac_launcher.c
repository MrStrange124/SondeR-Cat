/*  /\_/\    SondeR cat -- native macOS launcher
 * ( o.o )   Embeds the Python interpreter instead of exec-ing the venv's
 *           python, so the running process really IS "SondeR cat": that is
 * the name top / Activity Monitor / the crash reporter show, and the
 * identity System Settings lists under Accessibility, Input Monitoring and
 * Screen Recording (a plain shell wrapper hands all of that to "Python").
 *
 * Layout (built by install.sh):
 *   SondeR cat.app/Contents/MacOS/SondeR cat   <- this binary
 *   SondeR cat.app/Contents/pyvenv.cfg          <- makes the .app a venv
 *   SondeR cat.app/Contents/lib -> ../../.venv/lib
 *   SondeR cat.app/../sondercat.py              <- the cat
 *
 * Build:  clang -O2 -I<python include> mac_launcher.c <libpython dylib>
 *                -o "SondeR cat.app/Contents/MacOS/SondeR cat"
 */
#include <Python.h>
#include <mach-o/dyld.h>
#include <libgen.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    char exe[PATH_MAX], real[PATH_MAX];
    uint32_t n = sizeof(exe);
    if (_NSGetExecutablePath(exe, &n) != 0 || realpath(exe, real) == NULL) {
        fprintf(stderr, "SondeR cat: cannot locate myself\n");
        return 1;
    }
    /* .../SondeR cat.app/Contents/MacOS/<exe>  ->  project dir is 4 up */
    char project[PATH_MAX];
    strlcpy(project, real, sizeof(project));
    for (int i = 0; i < 4; i++) {
        char *slash = strrchr(project, '/');
        if (!slash) break;
        *slash = '\0';
    }
    char script[PATH_MAX];
    snprintf(script, sizeof(script), "%s/sondercat.py", project);
    if (access(script, R_OK) != 0) {
        fprintf(stderr, "SondeR cat: %s not found\n", script);
        return 1;
    }
    chdir(project);

    PyConfig config;
    char **py_argv;
    PyStatus st = {0};
    PyConfig_InitPythonConfig(&config);
    /* program_name -> the venv lookup (pyvenv.cfg beside / above the exe) */
    st = PyConfig_SetBytesString(&config, &config.program_name, real);
    if (PyStatus_Exception(st)) goto fail;
    st = PyConfig_SetBytesString(&config, &config.run_filename, script);
    if (PyStatus_Exception(st)) goto fail;
    /* argv exactly as the script sees it: [script, ...user args] */
    config.parse_argv = 0;
    py_argv = calloc(argc + 1, sizeof(char *));
    if (!py_argv) goto fail;
    py_argv[0] = script;
    for (int i = 1; i < argc; i++) py_argv[i] = argv[i];
    st = PyConfig_SetBytesArgv(&config, argc, py_argv);   /* copies */
    free(py_argv);
    if (PyStatus_Exception(st)) goto fail;
    st = Py_InitializeFromConfig(&config);
    if (PyStatus_Exception(st)) goto fail;
    PyConfig_Clear(&config);
    return Py_RunMain();
fail:
    PyConfig_Clear(&config);
    if (PyStatus_IsExit(st)) return st.exitcode;
    Py_ExitStatusException(st);
    return 1;
}
