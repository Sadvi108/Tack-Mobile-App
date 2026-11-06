import { assert, assertEquals } from "@std/assert";
import { fail } from "../util/http.ts";
import {
  listAll,
  PAGE,
  prefixesFor,
  PurgeError,
  runDeletion,
  type StorageEntry,
  type StoragePort,
} from "./purge.ts";

const UID = "6f1c2b9e-0d3a-4c55-9a7e-2b8f4e1d0c11";
const OTHER = "0a9b8c7d-6e5f-4a3b-8c2d-1e0f9a8b7c6d";

/**
 * Storage in memory, shaped like Supabase's: `list` returns one level at a
 * time (folders come back with a null id), honours limit and offset, and each
 * call can be made to fail.
 */
class FakeStorage implements StoragePort {
  readonly files: Record<string, Set<string>>;
  readonly listCalls: { bucket: string; prefix: string; offset: number }[] = [];
  readonly removeCalls: { bucket: string; paths: string[] }[] = [];
  failList: (bucket: string) => boolean = () => false;
  failRemove: (bucket: string) => boolean = () => false;
  /** Paths that `remove` reports as gone but quietly keeps. */
  readonly sticky = new Set<string>();

  constructor(files: Record<string, string[]>) {
    this.files = {
      documents: new Set(files.documents ?? []),
      avatars: new Set(files.avatars ?? []),
    };
  }

  list(
    bucket: string,
    prefix: string,
    page: { limit: number; offset: number },
  ): ReturnType<StoragePort["list"]> {
    this.listCalls.push({ bucket, prefix, offset: page.offset });
    if (this.failList(bucket)) {
      return Promise.resolve({ data: null, error: { message: "list failed" } });
    }
    const base = `${prefix}/`;
    const folders = new Set<string>();
    const entries: StorageEntry[] = [];
    for (const path of this.files[bucket] ?? []) {
      if (!path.startsWith(base)) continue;
      const rest = path.slice(base.length);
      const slash = rest.indexOf("/");
      if (slash === -1) entries.push({ name: rest, id: `obj:${path}` });
      else folders.add(rest.slice(0, slash));
    }
    for (const name of folders) entries.push({ name, id: null });
    entries.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
    return Promise.resolve({
      data: entries.slice(page.offset, page.offset + page.limit),
      error: null,
    });
  }

  remove(bucket: string, paths: string[]): ReturnType<StoragePort["remove"]> {
    this.removeCalls.push({ bucket, paths: [...paths] });
    if (this.failRemove(bucket)) {
      return Promise.resolve({ error: { message: "remove failed" } });
    }
    for (const path of paths) {
      if (!this.sticky.has(path)) this.files[bucket]?.delete(path);
    }
    return Promise.resolve({ error: null });
  }

  left(bucket: string, prefix: string): string[] {
    return [...this.files[bucket]].filter((p) => p.startsWith(`${prefix}/`));
  }
}

function deleter(error: string | null = null) {
  const calls: string[] = [];
  return {
    calls,
    deleteUser: (uid: string) => {
      calls.push(uid);
      return Promise.resolve({ error: error ? { message: error } : null });
    },
  };
}

function errorCode(body: Record<string, unknown>): unknown {
  return (body.error as { code?: unknown } | undefined)?.code;
}

/** Keeps the expected console.error lines out of the test output. */
async function quietly<T>(run: () => Promise<T>): Promise<T> {
  const original = console.error;
  console.error = () => {};
  try {
    return await run();
  } finally {
    console.error = original;
  }
}

Deno.test("documents live under users/<uid> and avatars under <uid>", () => {
  assertEquals(prefixesFor(UID), { documents: `users/${UID}`, avatars: UID });
});

Deno.test("a list error on the first bucket deletes nothing and says so", async () => {
  const storage = new FakeStorage({
    documents: [`users/${UID}/cv/1.pdf`],
    avatars: [`${UID}/a.png`],
  });
  storage.failList = (bucket) => bucket === "documents";
  const auth = deleter();

  const result = await quietly(() =>
    runDeletion({ storage, uid: UID, deleteUser: auth.deleteUser })
  );

  assertEquals(result.status, 502);
  assertEquals(errorCode(result.body), "delete_not_started");
  assertEquals(storage.removeCalls.length, 0);
  assertEquals(auth.calls.length, 0);
});

Deno.test("2,500 files two folders deep are all listed, removed in pages, then the user goes", async () => {
  const documents = Array.from(
    { length: 2500 },
    (_, i) => `users/${UID}/cv/2026/file-${String(i).padStart(4, "0")}.pdf`,
  );
  const storage = new FakeStorage({ documents });
  const auth = deleter();

  const result = await runDeletion({
    storage,
    uid: UID,
    deleteUser: auth.deleteUser,
  });

  assertEquals(result.status, 200);
  assertEquals(result.body, {
    deleted: true,
    files: { documents: 2500, avatars: 0 },
  });
  assertEquals(storage.left("documents", `users/${UID}`), []);
  assert(storage.removeCalls.every((c) => c.paths.length <= PAGE));
  assertEquals(storage.removeCalls.length, 3);
  const deepest = storage.listCalls
    .filter((c) => c.prefix === `users/${UID}/cv/2026`)
    .map((c) => c.offset);
  assert(deepest.includes(PAGE * 2), "paged past the first two pages");
  assertEquals(auth.calls, [UID]);
});

Deno.test("an avatar at <uid>/a.png is removed and other users' files are not touched", async () => {
  const storage = new FakeStorage({
    documents: [`users/${UID}/cv/1.pdf`, `users/${OTHER}/cv/2.pdf`],
    avatars: [`${UID}/a.png`, `${OTHER}/b.png`, `users/${UID}/stray.png`],
  });
  const auth = deleter();

  const result = await runDeletion({
    storage,
    uid: UID,
    deleteUser: auth.deleteUser,
  });

  assertEquals(result.status, 200);
  assertEquals(result.body, {
    deleted: true,
    files: { documents: 1, avatars: 1 },
  });
  assertEquals([...storage.files.avatars].sort(), [
    `${OTHER}/b.png`,
    `users/${UID}/stray.png`,
  ]);
  assertEquals([...storage.files.documents], [`users/${OTHER}/cv/2.pdf`]);
  const removed = storage.removeCalls.flatMap((c) =>
    c.paths.map((p) => `${c.bucket}:${p}`)
  );
  assertEquals(removed.sort(), [
    `avatars:${UID}/a.png`,
    `documents:users/${UID}/cv/1.pdf`,
  ]);
});

Deno.test("documents removed then avatars fail to list: incomplete, user kept, and a retry finishes", async () => {
  const storage = new FakeStorage({
    documents: [`users/${UID}/cv/1.pdf`, `users/${UID}/cover/2.pdf`],
    avatars: [`${UID}/a.png`],
  });
  storage.failList = (bucket) => bucket === "avatars";
  const auth = deleter();

  const first = await quietly(() =>
    runDeletion({ storage, uid: UID, deleteUser: auth.deleteUser })
  );

  assertEquals(first.status, 502);
  assertEquals(errorCode(first.body), "delete_incomplete");
  assertEquals(storage.left("documents", `users/${UID}`), []);
  assertEquals(auth.calls.length, 0);

  storage.failList = () => false;
  const retry = await runDeletion({
    storage,
    uid: UID,
    deleteUser: auth.deleteUser,
  });

  assertEquals(retry.status, 200);
  assertEquals(retry.body, {
    deleted: true,
    files: { documents: 0, avatars: 1 },
  });
  assertEquals(storage.left("avatars", UID), []);
  assertEquals(auth.calls, [UID]);
});

Deno.test("remove says it worked but a file is still there: fail and keep the user", async () => {
  const storage = new FakeStorage({
    documents: [`users/${UID}/cv/1.pdf`, `users/${UID}/cv/2.pdf`],
  });
  storage.sticky.add(`users/${UID}/cv/2.pdf`);
  const auth = deleter();

  const result = await quietly(() =>
    runDeletion({ storage, uid: UID, deleteUser: auth.deleteUser })
  );

  assertEquals(result.status, 502);
  assertEquals(errorCode(result.body), "delete_incomplete");
  assertEquals(auth.calls.length, 0);
});

Deno.test("deleting the auth user fails after a clean purge", async () => {
  const storage = new FakeStorage({ documents: [`users/${UID}/cv/1.pdf`] });
  const auth = deleter("auth is down");

  const result = await quietly(() =>
    runDeletion({ storage, uid: UID, deleteUser: auth.deleteUser })
  );

  assertEquals(result.status, 502);
  assertEquals(errorCode(result.body), "delete_account_failed");
  assertEquals(auth.calls, [UID]);
});

Deno.test("a remove error before anything is gone still says nothing was removed", async () => {
  const storage = new FakeStorage({
    documents: [`users/${UID}/cv/1.pdf`],
    avatars: [`${UID}/a.png`],
  });
  storage.failRemove = (bucket) => bucket === "documents";
  const auth = deleter();

  const result = await quietly(() =>
    runDeletion({ storage, uid: UID, deleteUser: auth.deleteUser })
  );

  assertEquals(result.status, 502);
  assertEquals(errorCode(result.body), "delete_not_started");
  assertEquals(storage.left("documents", `users/${UID}`).length, 1);
  assertEquals(auth.calls.length, 0);
});

Deno.test("a storage call that throws is a failure, not an empty folder", async () => {
  const storage = new FakeStorage({ documents: [`users/${UID}/cv/1.pdf`] });
  storage.list = () => Promise.reject(new Error("network down"));
  const auth = deleter();

  const result = await quietly(() =>
    runDeletion({ storage, uid: UID, deleteUser: auth.deleteUser })
  );

  assertEquals(result.status, 502);
  assertEquals(errorCode(result.body), "delete_not_started");
  assertEquals(auth.calls.length, 0);
});

Deno.test("listAll throws a PurgeError instead of returning an empty list", async () => {
  const storage = new FakeStorage({ avatars: [`${UID}/a.png`] });
  storage.failList = () => true;

  let caught: unknown;
  await quietly(async () => {
    try {
      await listAll(storage, "avatars", UID);
    } catch (e) {
      caught = e;
    }
  });

  assert(caught instanceof PurgeError);
  assertEquals(caught.stage, "list");
  assertEquals(caught.bucket, "avatars");
});

Deno.test("every failure body has the same shape fail() sends", async () => {
  const storage = new FakeStorage({ documents: [`users/${UID}/cv/1.pdf`] });
  storage.failList = () => true;

  const result = await quietly(() =>
    runDeletion({ storage, uid: UID, deleteUser: deleter().deleteUser })
  );
  const { message, code } = result.body.error as {
    message: string;
    code: string;
  };

  assertEquals(result.body, await fail(message, 502, code).json());
  assertEquals(
    message,
    "Your account could not be deleted just now. Nothing has been removed. " +
      "Try again in a moment.",
  );
});
