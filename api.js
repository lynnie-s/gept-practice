// 共用資料層：有填 Supabase 設定就用雲端，沒有就用試玩模式（localStorage）
(function () {
  const cfg = window.APP_CONFIG || {};
  const cloud = !!(cfg.SUPABASE_URL && cfg.SUPABASE_ANON_KEY && window.supabase);
  const sb = cloud ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY) : null;
  const LV = { e: "elementary", i: "intermediate" };
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
    async getWords(level) { return cloud ? fetchAll("words", level) : byLevel(await loadDemoWords(), level); },
    async getGrammar(level) { return cloud ? fetchAll("grammar_questions", level) : byLevel(await loadDemoGrammar(), level); },

    async saveAttempt(attempt, answers) {
      if (cloud) {
        const { data, error } = await sb.from("attempts").insert(attempt).select("id").single();
        if (error) throw error;
        const rows = answers.map(a => ({ ...a, attempt_id: data.id }));
        const { error: e2 } = await sb.from("attempt_answers").insert(rows);
        if (e2) throw e2;
        return data.id;
      }
      const list = LS("demo_attempts", []);
      const id = Date.now();
      list.push({ id, ...attempt, created_at: new Date().toISOString(), answers });
      SAVE("demo_attempts", list);
      return id;
    },

    // ---- 後台 ----
    async session() { if (!cloud) return { demo: true }; const { data } = await sb.auth.getSession(); return data.session; },
    async login(email, password) {
      if (!cloud) return { demo: true };
      const { data, error } = await sb.auth.signInWithPassword({ email, password });
      if (error) throw error;
      return data.session;
    },
    async logout() { if (cloud) await sb.auth.signOut(); },

    async listAttempts() {
      if (cloud) {
        const { data, error } = await sb.from("attempts").select("*").order("created_at", { ascending: false }).limit(2000);
        if (error) throw error;
        return data;
      }
      return LS("demo_attempts", []).slice().reverse().map(a => { const { answers, ...rest } = a; return rest; });
    },
    async getAnswers(attemptId) {
      if (cloud) {
        const { data, error } = await sb.from("attempt_answers").select("*").eq("attempt_id", attemptId).order("id");
        if (error) throw error;
        return data;
      }
      const a = LS("demo_attempts", []).find(x => x.id === attemptId);
      return a ? a.answers : [];
    },
    // 取得所有答錯紀錄（用來統計最常錯的題目）
    async allWrongAnswers() {
      if (cloud) {
        let out = [], from = 0, step = 1000;
        while (true) {
          const { data, error } = await sb.from("attempt_answers").select("qtype,qid,prompt,correct_answer,is_correct").range(from, from + step - 1);
          if (error) throw error;
          out = out.concat(data);
          if (data.length < step) break;
          from += step;
        }
        return out;
      }
      return LS("demo_attempts", []).flatMap(a => a.answers);
    },
    async deleteAttempt(id) {
      if (cloud) { const { error } = await sb.from("attempts").delete().eq("id", id); if (error) throw error; return; }
      SAVE("demo_attempts", LS("demo_attempts", []).filter(a => a.id !== id));
    },
    async importWords(rows) {
      if (!cloud) throw new Error("試玩模式不能匯入，請先設定 Supabase");
      for (let i = 0; i < rows.length; i += 500) {
        const { error } = await sb.from("words").upsert(rows.slice(i, i + 500), { onConflict: "word,meaning", ignoreDuplicates: true });
        if (error) throw error;
      }
    },
    async importGrammar(rows) {
      if (!cloud) throw new Error("試玩模式不能匯入，請先設定 Supabase");
      for (let i = 0; i < rows.length; i += 500) {
        const { error } = await sb.from("grammar_questions").insert(rows.slice(i, i + 500));
        if (error) throw error;
      }
    },
    async counts() {
      if (!cloud) return { words: (await loadDemoWords()).length, grammar: (await loadDemoGrammar()).length };
      const w = await sb.from("words").select("id", { count: "exact", head: true });
      const g = await sb.from("grammar_questions").select("id", { count: "exact", head: true });
      return { words: w.count || 0, grammar: g.count || 0 };
    }
  };
})();
