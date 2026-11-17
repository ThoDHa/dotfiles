# Probe: bwrap viability for raw task-storage isolation

**Task:** ORCH-4-10-1-20261106-1716-feasibility-probes-and-walking-skeleton.md
**Date:** 2026-11-17
**Operator:** worker-orch4-10-1
**Machine facts:** bubblewrap 0.11.1 (/usr/bin/bwrap), Linux, `kernel.unprivileged_userns_clone = 1`, no AppArmor user-namespace denial observed. Raw capture logs: `/tmp/llm/orch4-10-1-scratch/p2/` (session scratch; transcribed here).

## P1: Unprivileged user namespace viability

```
$ bwrap --unshare-all --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp /bin/echo P1-OK
P1-OK
exit=0
$ bwrap --unshare-user --unshare-ipc --unshare-pid --unshare-net --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp /bin/echo P1b-OK-no-mount-unshare
P1b-OK-no-mount-unshare
exit=0
$ sysctl kernel.unprivileged_userns_clone
kernel.unprivileged_userns_clone = 1
```

Verdict: unprivileged user namespaces are fully viable on this machine, including mount and network unshare.

## Fixture (P2 through P5)

A real git repo at `/tmp/llm/orch4-10-1-scratch/p2/repo`: tracked `README.md` and `.gitignore` (`.tasks/` gitignored), untracked `.tasks/board.md` and `.tasks/current/secret.md` (content marker `masked-fixture-payload`). Commit `3b91295`.

## P2: tmpfs mask of a gitignored directory inside a git repo

Control without the mask (P2a):

```
$ bwrap --unshare-all --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp \
    --ro-bind $REPO $REPO cat $REPO/.tasks/current/secret.md
masked-fixture-payload
exit=0
```

With `--tmpfs` stacked over `.tasks` (P2b):

```
$ bwrap --unshare-all --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp \
    --ro-bind $REPO $REPO --tmpfs $REPO/.tasks \
    sh -c "ls -la $REPO/.tasks/; cat $REPO/.tasks/current/secret.md"
total 0
drwxr-xr-x 2 khave khave  40 Nov 17 07:33 .
drwxrwxr-x 4 khave khave 120 Nov 17 07:33 ..
cat: /tmp/llm/orch4-10-1-scratch/p2/repo/.tasks/current/secret.md: No such file or directory
exit=1
```

Repo function under the mask (P2c, P2d, P2e):

```
$ ... --tmpfs $REPO/.tasks git -C $REPO status --porcelain
exit=0                      (clean; the masked tree is invisible to git as designed)
$ ... --tmpfs $REPO/.tasks node --version
v24.22.0
exit=0
$ ... --tmpfs $REPO/.tasks ~/.local/bin/tasks --help
Usage: tasks <command> [options]
...
exit=0
```

Verdict: a tmpfs mount over the gitignored `.tasks` directory denies direct reads while git, node, and the tasks CLI stay functional inside the namespace.

## P3: symlink traversal through the mask

Pre-created in the fixture: `link-rel -> .tasks/current/secret.md` (repo root), `link-abs -> $REPO/.tasks/current/secret.md` (absolute), `sub/deeper/link-updown -> ../../.tasks/current/secret.md` (parent traversal). All reads under the same mask:

```
$ ... --tmpfs $REPO/.tasks cat $REPO/link-rel
cat: /tmp/llm/orch4-10-1-scratch/p2/repo/link-rel: No such file or directory
exit=1
$ ... --tmpfs $REPO/.tasks cat $REPO/link-abs
cat: /tmp/llm/orch4-10-1-scratch/p2/repo/link-abs: No such file or directory
exit=1
$ ... --tmpfs $REPO/.tasks cat $REPO/sub/deeper/link-updown
cat: /tmp/llm/orch4-10-1-scratch/p2/repo/sub/deeper/link-updown: No such file or directory
exit=1
$ ... --tmpfs $REPO/.tasks python3 -c "import os; p='$REPO/link-rel'; print(os.path.realpath(p)); open(p).read()"
/tmp/llm/orch4-10-1-scratch/p2/repo/.tasks/current/secret.md
FileNotFoundError: [Errno 2] No such file or directory: '/tmp/llm/orch4-10-1-scratch/p2/repo/link-rel'
exit=1
```

Verdict: the mask holds during path resolution, so every symlink class (relative, absolute, parent traversal) resolves into the empty tmpfs and is denied; realpath normalization cannot escape it. No lexical path guard is needed against the masked tree.

## P4: AF_UNIX escape channel under full unshare

Server binds `$RUN/echo.sock` on the host; client runs inside `--unshare-all` with the socket FILE bind-mounted over the `/tmp` tmpfs (plus the client script itself):

```
$ bwrap --unshare-all --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp \
    --bind $RUN/echo.sock $RUN/echo.sock --bind $RUN/p4-client.py $RUN/p4-client.py \
    python3 $RUN/p4-client.py $RUN/echo.sock
P4-SERVICE-REPLY:ping-from-sandbox
exit=0
```

Verdict: AF_UNIX connects work under full namespace unsharing through a bound socket file; a parent-side socket service is a viable escape channel. Note for mechanism design: bind the socket FILE (least privilege), never the scratch directory; `--tmpfs /tmp` plus later stacked `--bind` arguments is the ordering that works.

## P5: Skeleton-candidate namespace shape (network shared)

Model-bound children need the network for the LLM gateway, so `--unshare-net` must be dropped for LLM-driven children. Shape: `--unshare-user --unshare-ipc --unshare-pid` plus the mask:

```
$ bwrap --unshare-user --unshare-ipc --unshare-pid --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp \
    --ro-bind $REPO $REPO --tmpfs $REPO/.tasks \
    sh -c "cat $REPO/.tasks/current/secret.md; curl -sS -o /dev/null -w '%{http_code}' https://api.github.com --max-time 8; echo; node --version"
cat: /tmp/llm/orch4-10-1-scratch/p2/repo/.tasks/current/secret.md: No such file or directory
200
v24.22.0
exit=0
```

Verdict: with the network namespace shared, the mask still denies direct reads and outbound HTTPS works. This is the shape the walking skeleton uses.

## Bwrap argument-ordering findings

Mounts stack in argument order: a later `--tmpfs` or `--bind` shadows earlier views of the same path. The working order is: ro-bind `/`, dev/proc, `--tmpfs /tmp`, ro-bind the fixture repo, `--tmpfs $REPO/.tasks` (the mask, stacked over the repo bind), then least-privilege `--bind` entries for exactly the sanctioned-escape artifacts (socket file). Everything under `/tmp` outside explicit binds is invisible to the child.

## Child-wrap runtime requirements discovered during skeleton bring-up

Two findings from running a real pi child under the mask (skeleton iterations, machine evidence in the run transcripts):

1. pi child startup requires a writable `~/.pi/agent`: it creates the `trust.json.lock` lock (mkdir-based) under a ro-bind of `/`, which fails with `EROFS` and kills the child. bwrap 0.11.1 has no `--create` flag and cannot create missing bind destinations under a read-only mount (`bwrap: Can't mkdir ...: Read-only file system`), so pre-binding a scratch lock path does not work. The working shape: `--tmpfs` over `~/.pi/agent` (making it writable), every real entry ro-bound back in, and a scratch `trust.json` bound on top. The ORCH-4-10-2 child-wrap needs this trust-state provision (or an equivalent pi-side trust-disable flag) or masked children cannot start.
2. The model id namespace differs per harness: the fleet worker agent compiles to pi model id `glm-5.3-flash` (provider prefix `zai/` for direct pi `--model` use), while opencode's map uses `zai-coding-plan/glm-5.3-flash`.
