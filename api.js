// 共用資料層：有填 Supabase 設定就用雲端，沒有就用試玩模式（localStorage）
(function () {
  const cfg = window.APP_CONFIG || {};
  const cloud = !!(cfg.SUPABASE_URL && cfg.SUPABASE_ANON_KEY && window.supabase);
  const sb = cloud ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY) : null;
  const LV = { e: "elementary", i: "intermediate" };
  const uuid = () => (window.crypto && crypto.randomUUID) ? crypto.randomUUID()
    : "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === "x" ? r : (r & 3 | 8)).toString(16); });
  const LS = (k, d) => { try { return JSON.parse(localStorage.getItem(k)) ?? d; } catch (e) { return d; } };
  const SAVE = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} };

  async function fetchAll(table, level) {
    let out = [], from = 0, step = 1000;
    while (true) {
      let q = sb.from(table).select("*").range(from, from + step - 1);
      if (level && level !== "all") q = q.eq("level", level);
      const { data, error } = await q;
      if (error) throw error;
      out = out.concat(data);
      if (data.length < step) break;
      from += step;
    }
    return out;
  }

  // 試玩模式：優先用完整官方單字表（wordlist.js，用到才載入），沒有就退回範例
  let demoWordCache = null;
  async function loadDemoWords() {
    if (demoWordCache) return demoWordCache;
    if (!window.GEPT_WORDS) {
      await new Promise(res => { const s = document.createElement("script"); s.src = "wordlist.js"; s.onload = res; s.onerror = res; document.head.appendChild(s); });
    }
    const src = window.GEPT_WORDS || window.SAMPLE_WORDS || [];
    demoWordCache = src.map((r, i) => ({ id: i + 1, word: r[0], pos: r[1], meaning: r[2], level: LV[r[3]] }));
    return demoWordCache;
  }
  // 試玩模式：優先用完整文法題庫（grammarlist.js，用到才載入），沒有就退回範例
  let demoGrammarCache = null;
  async function loadDemoGrammar() {
    if (demoGrammarCache) return demoGrammarCache;
    if (!window.GEPT_GRAMMAR) {
      await new Promise(res => { const s = document.createElement("script"); s.src = "grammarlist.js"; s.onload = res; s.onerror = res; document.head.appendChild(s); });
    }
    const src = window.GEPT_GRAMMAR || window.SAMPLE_GRAMMAR || [];
    demoGrammarCache = src.map((r, i) => ({
      id: i + 1, question: r[0], opt_a: r[1], opt_b: r[2], opt_c: r[3], opt_d: r[4], answer: r[5], explanation: r[6], topic: r[7], level: LV[r[8]]
    }));
    return demoGrammarCache;
  }
  const byLevel = (arr, level) => (level && level !== "all" ? arr.filter(x => x.level === level) : arr);

  window.API = {
    cloud,
    sb,
    async getWords(level) { return cloud ? fetchAll("gept_words", level) : byLevel(await loadDemoWords(), level); },
    async getGrammar(level) { return cloud ? fetchAll("gept_grammar_questions", level) : byLevel(await loadDemoGrammar(), level); },

    async saveAttempt(attempt, answers) {
      // 學生是匿名身分，沒有「讀取成績」的權限，所以編號由學生端產生，寫入時不要求回傳資料
      const id = uuid();
      if (cloud) {
        const { error } = await sb.from("gept_attempts").insert({ id, ...attempt });
        if (error) throw error;
        const rows = answers.map(a => ({ ...a, attempt_id: id }));
        const { error: e2 } = await sb.from("gept_attempt_answers").insert(rows);
        if (e2) throw e2;
        return id;
      }
      const list = LS("demo_attempts", []);
      list.push({ id, ...attempt, created_at: new Date().toISOString(), answers });
      SAVE("demo_attempts", list);
      return id;
    },

    // ---- 後台（用老師密碼，不需要帳號）----
    canDelete: !cloud,   // 雲端模式未開放刪除（資料庫沒有刪除函式），試玩模式可刪
    code() { try { return localStorage.getItem("gept_teacher_code") || ""; } catch (e) { return ""; } },
    async rpc(fn, args) {
      const { data, error } = await sb.rpc(fn, { p_code: this.code(), ...(args || {}) });
      if (error) throw error;
      return data;
    },
    async session() {
      if (!cloud) return { demo: true };
      if (!this.code()) return null;
      try { return (await sb.rpc("gept_admin_login", { p_code: this.code() })).data === "ok" ? { ok: true } : null; } catch (e) { return null; }
    },
    async login(code) {
      if (!cloud) return { demo: true };
      const c = String(code || "").trim();
      if (!c) throw new Error("請輸入老師密碼");
      const { data, error } = await sb.rpc("gept_admin_login", { p_code: c });
      if (error) throw error;
      if (data === "locked") throw new Error("輸入錯誤太多次，請 10 分鐘後再試");
      if (data !== "ok") throw new Error("密碼不對");
      try { localStorage.setItem("gept_teacher_code", c); } catch (e) {}
      return { ok: true };
    },
    async logout() { try { localStorage.removeItem("gept_teacher_code"); } catch (e) {} },

    async listAttempts() {
      if (cloud) return (await this.rpc("gept_admin_list_attempts")) || [];
      return LS("demo_attempts", []).slice().reverse().map(a => { const { answers, ...rest } = a; return rest; });
    },
    async getAnswers(attemptId) {
      if (cloud) return (await this.rpc("gept_admin_get_answers", { p_attempt: attemptId })) || [];
      const a = LS("demo_attempts", []).find(x => x.id === attemptId);
      return a ? a.answers : [];
    },
    // 每一題被作答幾次、答錯幾次：[{qtype,qid,prompt,correct_answer,n,w}]
    async wrongStats() {
      if (cloud) return ((await this.rpc("gept_admin_wrong_stats")) || []).map(r => ({ ...r, n: Number(r.n), w: Number(r.w) }));
      const map = {};
      LS("demo_attempts", []).flatMap(a => a.answers).forEach(r => {
        const k = r.qtype + "#" + r.qid;
        const o = map[k] = map[k] || { qtype: r.qtype, qid: r.qid, prompt: r.prompt, correct_answer: r.correct_answer, n: 0, w: 0 };
        o.n++; if (!r.is_correct) o.w++;
      });
      return Object.values(map);
    },
    async deleteAttempt(id) {
      if (cloud) throw new Error("雲端模式暫不提供刪除");
      SAVE("demo_attempts", LS("demo_attempts", []).filter(a => a.id !== id));
    },
    async _import(fn, rows) {
      for (let i = 0; i < rows.length; i += 500) {
        const r = await this.rpc(fn, { p_rows: rows.slice(i, i + 500) });
        if (r === -1) throw new Error("密碼不對或已被鎖定");
        if (r < 0) throw new Error("匯入失敗（代碼 " + r + "）");
      }
    },
    async importWords(rows) {
      if (!cloud) throw new Error("試玩模式不能匯入，請先設定 Supabase");
      return this._import("gept_admin_import_words", rows);
    },
    async importGrammar(rows) {
      if (!cloud) throw new Error("試玩模式不能匯入，請先設定 Supabase");
      return this._import("gept_admin_import_grammar", rows);
    },
    async counts() {
      if (!cloud) return { words: (await loadDemoWords()).length, grammar: (await loadDemoGrammar()).length };
      const w = await sb.from("gept_words").select("id", { count: "exact", head: true });
      const g = await sb.from("gept_grammar_questions").select("id", { count: "exact", head: true });
      return { words: w.count || 0, grammar: g.count || 0 };
    }
  };
})();
