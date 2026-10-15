# 全民英檢初中級 單字＋文法練習站

學生端：index.html（輸入名字，選單字／文法／綜合／錯題本，每回 30 題，答完馬上看對錯，有發音按鈕）
老師後台：admin.html（成績紀錄、點開看學生答錯哪幾題、學生總覽、最常錯的題目、匯出 CSV、匯入題庫）

## 先試玩（不用設定）
沒有填 Supabase 設定（config.js 留空）時，直接雙擊 index.html 就能玩，這時是「試玩模式」：用內建的官方單字表與 253 題文法題，成績只存在這台瀏覽器。

## 正式上線（GitHub + Supabase）
後端已建在 Supabase 專案 gept-practice，config.js 已填好網址與公開金鑰，資料表與安全規則都套用完成（schema.sql 是備份）。剩下：
1. 到 Supabase 的 Authentication > Users > Add user，用老師的 email 和密碼建立帳號。
2. 到 SQL Editor 執行：insert into public.teachers(email) values ('老師的email');
   只有名單內的 email 才看得到成績。Supabase 預設任何人都能註冊，所以這一步不能省。
3. 建議到 Authentication 的設定把「Allow new users to sign up」關掉。
4. 打開 admin.html 用老師帳號登入，到「題庫管理」匯入 gept-words-all.csv 與 gept-grammar-all.csv。
5. 整個資料夾 push 到 GitHub，Settings > Pages 選 main 分支就有網址（純靜態，不用 build）。

## 單字來源
官方 LTTC 初級、中級單字表（共 5,083 筆，不重複的字 4,756 個，初級 2,397 筆、中級 2,686 筆；中級表本身已包含初級）：
- 初級：https://www.lttc.ntu.edu.tw/resources/GEPT/GEPT_Elementary.pdf
- 中級：https://www.lttc.ntu.edu.tw/resources/GEPT/GEPT_Intermediate.pdf
已整理成 gept-words-all.csv（word,pos,meaning,level），到後台「題庫管理」匯入「單字」即可，重複會自動略過。
試玩模式（還沒設定 Supabase）會直接用同一份單字表（wordlist.js）。

## 題庫 CSV
- 單字：gept-words-all.csv（官方完整單字表），words-template.csv 是格式範例
- 文法：gept-grammar-all.csv（內建 253 題，初級 126、中級 127，47 個主題），grammar-template.csv 是格式範例（question,opt_a,opt_b,opt_c,opt_d,answer,explanation,topic,level）
- level 填 elementary（初級）或 intermediate（中級）；answer 填 A/B/C/D
- 單字重複會自動略過，可以分批匯入

## 安全性說明
學生不用登入，只能「讀題庫」跟「新增自己的成績」，看不到別人的成績。只有登入的老師帳號能讀成績與改題庫（schema.sql 的 RLS 規則）。學生名字是自己輸入的，所以同名會被當成同一個人。

## 檔案
- index.html 學生端 / admin.html 老師後台 / api.js 資料層 / config.js 設定
- data.js 試玩用範例題庫 / schema.sql 資料庫 / *.csv 匯入範本
