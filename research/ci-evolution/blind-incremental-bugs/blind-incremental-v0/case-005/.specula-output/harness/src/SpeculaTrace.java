/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements. See the NOTICE file distributed
 * with this work for additional information regarding copyright ownership.
 * The ASF licenses this file to you under the Apache License, Version 2.0.
 */
package org.apache.zookeeper.server;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.PrintWriter;
import java.io.UnsupportedEncodingException;

/** Disabled-by-default, process-wide NDJSON trace sink for the Specula harness. */
public final class SpeculaTrace {
    private static final String TRACE_FILE = System.getProperty("specula.trace.file");
    private static PrintWriter writer;

    private SpeculaTrace() {
    }

    private static String quote(String value) {
        if (value == null) {
            return "";
        }
        return value.replace("\\", "\\\\").replace("\"", "\\\"")
                .replace("\n", "\\n").replace("\r", "\\r");
    }

    private static String node(long id) {
        return id < 0 ? "" : "s" + Long.toString(id);
    }

    private static PrintWriter writer() {
        if (TRACE_FILE == null || TRACE_FILE.length() == 0) {
            return null;
        }
        if (writer == null) {
            try {
                File target = new File(TRACE_FILE);
                File parent = target.getParentFile();
                if (parent != null && !parent.exists() && !parent.mkdirs()) {
                    throw new IllegalStateException("cannot create trace directory " + parent);
                }
                writer = new PrintWriter(target, "UTF-8");
            } catch (FileNotFoundException e) {
                throw new IllegalStateException("cannot open Specula trace", e);
            } catch (UnsupportedEncodingException e) {
                throw new IllegalStateException("UTF-8 unavailable", e);
            }
        }
        return writer;
    }

    public static synchronized void emit(String name, long nid, long zxid,
            long peer, long epoch, long acceptedEpoch, String role, String mode) {
        PrintWriter out = writer();
        if (out == null) {
            return;
        }
        out.print("{\"tag\":\"trace\",\"ts\":");
        out.print(System.nanoTime());
        out.print(",\"event\":{\"name\":\"");
        out.print(quote(name));
        out.print("\",\"nid\":\"");
        out.print(node(nid));
        out.print("\",\"peer\":\"");
        out.print(node(peer));
        out.print("\",\"state\":{\"zxid\":");
        out.print(zxid);
        out.print(",\"epoch\":");
        out.print(epoch);
        out.print(",\"acceptedEpoch\":");
        out.print(acceptedEpoch);
        out.print(",\"role\":\"");
        out.print(quote(role));
        out.print("\",\"mode\":\"");
        out.print(quote(mode));
        out.println("\"}}}");
        out.flush();
        if (out.checkError()) {
            throw new IllegalStateException("failed writing Specula trace " + TRACE_FILE);
        }
    }
}
