# 全民英檢初中級 單字＋文法練習站

學生端：index.html（輸入名字，選單字／文法／綜合／錯題本，每回 30 題，答完馬上看對錯，有發音按鈕）
老師後台：admin.html（成績紀錄、點開看學生答錯哪幾題、學生總覽、最常錯的題目、匯出 CSV、匯入題庫）

## 先試玩（不用設定）
沒有填 Supabase 設定（config.js 留空）時，直接雙擊 index.html 就能玩，這時是「試玩模式」：用內建的官方單字表與 253 題文法題，成績只存在這台瀏覽器。

## 正式上線（GitHub + Supabase）
後端放在 Supabase 專案 daruma（英檢的表都以 gept_ 開頭，與 daruma 原有資料分開），config.js 已填好網址與公開金鑰，資料表與安全規則都套用完成（schema.sql 是備份）。剩下：
1. 整個資料夾 push 到 GitHub，Settings > Pages 選 main 分支就有網址（純靜態，不用 build）。
2. 老師的後台網址是「學生網址」後面加 /admin.html。前台首頁沒有任何後台連結，請只傳給老師。
3. 第一次打開 admin.html 輸入老師密碼，同一個瀏覽器之後會記住。
4. 到「題庫管理」匯入 gept-words-all.csv 與 gept-grammar-all.csv（只要做一次，重複匯入會自動略過）。

## 老師密碼
- 後台不需要帳號，只要密碼。密碼只以加密後的雜湊存在資料庫，檔案裡沒有。
- 同一個 IP 10 分鐘內輸錯 10 次會暫時鎖住。
- 更換密碼：到 Supabase SQL Editor 執行
  update public.gept_admin_secret set hash = extensions.crypt(upper('新密碼'), extensions.gen_salt('bf', 8)) where id = 1;
- 目前雲端模式的後台沒有「刪除成績」功能（資料庫端沒開刪除函式）。需要時可以到 Supabase 的 Table Editor 手動刪。

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
學生不用登入，只能「讀題庫」跟「新增自己的成績」，看不到別人的成績。成績只能透過需要老師密碼的資料庫函式讀取，匿名直接查表會被擋掉（schema.sql 的 RLS 規則）。學生名字是自己輸入的，所以同名會被當成同一個人。

## 檔案
- index.html 學生端 / admin.html 老師後台 / api.js 資料層 / config.js 設定
- data.js 試玩用範例題庫 / schema.sql 資料庫 / *.csv 匯入範本
