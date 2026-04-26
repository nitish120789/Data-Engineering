-- Top SQL from AWR
SELECT * FROM dba_hist_sqlstat ORDER BY elapsed_time_delta DESC FETCH FIRST 10 ROWS ONLY;