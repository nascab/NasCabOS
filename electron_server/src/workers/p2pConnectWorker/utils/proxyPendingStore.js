class ProxyPendingStore {
  constructor() {
    this.pendingReqBodiesByPrefix = new Map();
    this.pendingStreamsByPrefix = new Map();
    this.pendingRemoteCandidatesBySession = new Map();
  }

  getPendingKey(sessionId, prefix) {
    const sid = sessionId == null ? '' : String(sessionId);
    const p = prefix == null ? '' : String(prefix);
    return `${sid}::${p}`;
  }

  getPendingReqBodies(sessionId, prefix) {
    const key = this.getPendingKey(sessionId, prefix);
    if (!this.pendingReqBodiesByPrefix.has(key)) {
      this.pendingReqBodiesByPrefix.set(key, new Map());
    }
    return this.pendingReqBodiesByPrefix.get(key);
  }

  getPendingStreams(sessionId, prefix) {
    const key = this.getPendingKey(sessionId, prefix);
    if (!this.pendingStreamsByPrefix.has(key)) {
      this.pendingStreamsByPrefix.set(key, new Map());
    }
    return this.pendingStreamsByPrefix.get(key);
  }

  cleanupProxyPendingForSession(sessionId) {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid) return;
    const prefix = `${sid}::`;

    try {
      for (const [k, pendingReqBodies] of this.pendingReqBodiesByPrefix.entries()) {
        if (!k || !k.startsWith(prefix)) continue;
        try {
          for (const [, st] of pendingReqBodies.entries()) {
            try {
              if (st && st.timeoutId) clearTimeout(st.timeoutId);
            } catch (_) {}
          }
        } catch (_) {}
        try {
          pendingReqBodies.clear();
        } catch (_) {}
        this.pendingReqBodiesByPrefix.delete(k);
      }
    } catch (_) {}

    try {
      for (const [k, pendingStreams] of this.pendingStreamsByPrefix.entries()) {
        if (!k || !k.startsWith(prefix)) continue;
        try {
          for (const [, st] of pendingStreams.entries()) {
            try {
              if (st && st.abortController && typeof st.abortController.abort === 'function') st.abortController.abort();
            } catch (_) {}
            try {
              if (st && st.stream && typeof st.stream.destroy === 'function') st.stream.destroy();
            } catch (_) {}
            const resumeWaiters = st && Array.isArray(st.resumeWaiters) ? st.resumeWaiters.splice(0, st.resumeWaiters.length) : [];
            const creditWaiters = st && Array.isArray(st.creditWaiters) ? st.creditWaiters.splice(0, st.creditWaiters.length) : [];
            for (const fn of resumeWaiters) {
              try {
                fn();
              } catch (_) {}
            }
            for (const fn of creditWaiters) {
              try {
                fn();
              } catch (_) {}
            }
          }
        } catch (_) {}
        try {
          pendingStreams.clear();
        } catch (_) {}
        this.pendingStreamsByPrefix.delete(k);
      }
    } catch (_) {}
  }

  pushPendingRemoteCandidate(sessionId, candidate) {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid || !candidate) return;
    const arr = this.pendingRemoteCandidatesBySession.get(sid) || [];
    arr.push(candidate);
    if (arr.length > 256) arr.splice(0, arr.length - 256);
    this.pendingRemoteCandidatesBySession.set(sid, arr);
  }

  drainPendingRemoteCandidates(sessionId) {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid) return [];
    const arr = this.pendingRemoteCandidatesBySession.get(sid) || [];
    this.pendingRemoteCandidatesBySession.delete(sid);
    return arr;
  }
}

module.exports = { ProxyPendingStore };
