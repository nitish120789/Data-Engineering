"""Build an AWR-style HTML report from a detailed TXT report.

Usage:
        python report_builder_stub.py --engine mysql --input report.txt --output report.html
"""
from __future__ import annotations

import argparse
import html
import re
from datetime import datetime, timezone
from pathlib import Path


def parse_sections(report_text: str) -> list[tuple[str, str]]:
        sections: list[tuple[str, str]] = []
        current_title = "Overview"
        current_lines: list[str] = []

        for raw_line in report_text.splitlines():
                line = raw_line.rstrip("\n")
                if line.startswith("## "):
                        if current_lines:
                                sections.append((current_title, "\n".join(current_lines).strip()))
                        current_title = line[3:].strip()
                        current_lines = []
                        continue
                current_lines.append(line)

        if current_lines:
                sections.append((current_title, "\n".join(current_lines).strip()))
        return sections


def build_findings(report_text: str) -> tuple[list[str], str]:
        findings: list[str] = []
        lower = report_text.lower()

        if "section unavailable" in lower:
                findings.append("Some sections were unavailable due to privileges, feature flags, or engine/version differences.")
        if "deadlock" in lower:
                findings.append("Deadlock signals were detected; review lock chains and top contending statements.")
        if "lock wait" in lower or "row_lock" in lower:
                findings.append("Lock wait pressure detected; investigate blocking sessions and transaction scope.")
        if "log waits" in lower:
                findings.append("Redo/log write pressure may be present; validate IOPS and log file throughput.")
        if "tmp_disk" in lower or "tmp table" in lower:
                findings.append("Temporary object usage observed; inspect sort/hash memory limits and query patterns.")
        if "blocking_session_id" in lower or "head blocker" in lower:
                findings.append("Blocking chain data is present; check head blockers, transaction scope, and lock duration.")
        if "memory grants pending" in lower or "resource_semaphore" in lower:
                findings.append("Memory grant pressure indicators are present; inspect grant queues and large query concurrency.")
        if "pageiolatch" in lower or "io/log" in lower or "writelog" in lower:
                findings.append("IO or log-write pressure indicators are present; correlate file latency with top read/write statements.")
        if "query store" in lower:
                findings.append("Query Store data is available; compare runtime outliers and plan regressions against recent change windows.")
        if "innodb_deadlocks" in lower or "innodb_row_lock_waits" in lower:
                findings.append("InnoDB deadlock or row lock wait pressure detected; investigate lock order and transaction scope.")
        if "created_tmp_disk_tables" in lower:
                findings.append("Temporary disk table usage detected; consider raising tmp_table_size/max_heap_table_size.")
        if "innodb_log_waits" in lower:
                findings.append("InnoDB log wait pressure present; consider increasing innodb_log_buffer_size.")
        if "select_full_join" in lower or "no_index_used" in lower:
                findings.append("Full-table scan or no-index-used signals present; review query plans and index coverage.")
        if "slave_sql_running" in lower or "replica_sql_running" in lower:
                findings.append("Replication data is present; validate replica lag and IO/SQL thread state.")
        if "wal_buffers_full" in lower or "checkpoints_req" in lower:
                findings.append("PostgreSQL WAL/checkpoint pressure signals detected; review checkpoint cadence and write bursts.")
        if "n_dead_tup" in lower or "autovacuum" in lower:
                findings.append("Table bloat or autovacuum pressure may be present; inspect dead tuples and vacuum throughput.")
        if "aggregate pga" in lower or "over allocation count" in lower:
                findings.append("Oracle PGA pressure indicators detected; validate memory targets and workarea policy.")
        if "tablespace" in lower and "used_percent" in lower:
                findings.append("Tablespace utilization data present; review high used-percent tablespaces for capacity risk.")

        if not findings:
                findings.append("No explicit high-risk indicators were auto-detected; validate against workload SLO baselines.")

        recommendation = (
                "Prioritize sections with elevated wait/lock/error counters, compare against previous runs, "
                "and correlate with deployment and traffic changes in the report window."
        )
        return findings, recommendation


def render_html(engine: str, report_text: str, sections: list[tuple[str, str]]) -> str:
        findings, recommendation = build_findings(report_text)
        generated = datetime.now(timezone.utc).isoformat()

        def extract_key_value_pairs(content: str) -> list[tuple[str, str]]:
                pairs: list[tuple[str, str]] = []
                for line in content.splitlines():
                        if ":" not in line:
                                continue
                        key, value = line.split(":", 1)
                        key = key.strip()
                        value = value.strip()
                        if key and value:
                                pairs.append((key, value))
                return pairs

        def looks_like_rule(line: str) -> bool:
                cleaned = line.replace("|", "").replace(" ", "")
                return bool(cleaned) and set(cleaned) <= {"-"}

        def parse_table_block(lines: list[str]) -> tuple[list[str], list[list[str]]] | None:
                if len(lines) < 2 or "|" not in lines[0] or not looks_like_rule(lines[1]):
                        return None
                headers = [part.strip() for part in lines[0].split("|")]
                rows: list[list[str]] = []
                for raw in lines[2:]:
                        if not raw.strip() or "|" not in raw:
                                continue
                        cells = [part.strip() for part in raw.split("|")]
                        if len(cells) != len(headers):
                                continue
                        rows.append(cells)
                if not rows:
                        return None
                return headers, rows

        def parse_content_blocks(content: str) -> list[tuple[str, object]]:
                blocks: list[tuple[str, object]] = []
                current: list[str] = []

                def flush() -> None:
                        nonlocal current
                        if not current:
                                return
                        table = parse_table_block(current)
                        if table:
                                blocks.append(("table", table))
                        else:
                                text = "\n".join(current).strip()
                                if text:
                                        blocks.append(("text", text))
                        current = []

                for line in content.splitlines():
                        if not line.strip():
                                flush()
                                continue
                        current.append(line)
                flush()
                return blocks

        def summarize_section(title: str, content: str) -> str:
                lower_title = title.lower()
                lower_content = content.lower()
                if "wait" in lower_title:
                        return "Primary wait pressure across tasks, categories, and active chains."
                if "active requests" in lower_title or "ash" in lower_title:
                        return "Current workload sample showing sessions, waits, and top in-flight statements."
                if "cpu" in lower_title or "duration" in lower_title or "read and write" in lower_title:
                        return "High-cost statements ranked by resource consumption and runtime impact."
                if "blocking" in lower_title or "deadlock" in lower_title:
                        return "Concurrency diagnostics for blockers, victims, and transaction contention."
                if "memory" in lower_title or "tempdb" in lower_title:
                        return "Memory grant, buffer, and workspace pressure indicators."
                if "alwayson" in lower_title or "replica" in lower_title:
                        return "Availability group synchronization and replica health status."
                if "io" in lower_title or "log" in lower_title:
                        return "Storage latency, file pressure, and recovery/log utilization signals."
                if "query store" in lower_title:
                        return "Plan/runtime history useful for regression and outlier detection."
                if "buffer pool" in lower_title:
                        return "InnoDB buffer pool utilization, hit ratio, and dirty page pressure."
                if "innodb io" in lower_title or "log pressure" in lower_title:
                        return "InnoDB IO, redo log, and page operation pressure indicators."
                if "statement wait" in lower_title:
                        return "Performance Schema wait events sorted by cumulative wait time - analogous to AWR Top Wait Events."
                if "lock wait" in lower_title or "transaction" in lower_title:
                        return "Concurrency diagnostics: InnoDB lock waits, deadlocks, and long-running transactions."
                if "table io" in lower_title:
                        return "Per-table read/write latency - analogous to AWR Segment IO statistics."
                if "wal" in lower_title or "checkpoint" in lower_title:
                        return "WAL generation and checkpoint behavior indicating write pressure and durability cadence."
                if "vacuum" in lower_title or "analyze" in lower_title:
                        return "Autovacuum and statistics maintenance posture for bloat and planner stability."
                if "slot health" in lower_title:
                        return "Replication slot and stream health, including lag and retention risk indicators."
                if "sga" in lower_title or "pga" in lower_title:
                        return "Oracle memory pool sizing and pressure indicators across SGA/PGA components."
                if "tablespace" in lower_title:
                        return "Tablespace usage posture and free-space pressure hotspots."
                if "undo" in lower_title:
                        return "Undo retention pressure and transaction rollback segment health signals."
                if "user and host" in lower_title or "session mix" in lower_title:
                        return "User/host session distribution and activity breakdown."
                if "schema" in lower_title or "inventory" in lower_title:
                        return "Object inventory, sizing, and storage allocation."
                if "binary log" in lower_title:
                        return "Binary log status, GTID state, and log file inventory."
                if "replication" in lower_title:
                        return "Replication channel state, lag, and IO/SQL thread health."
                if "rows examined" in lower_title or "execution count" in lower_title or "temp disk" in lower_title or "errors" in lower_title:
                        return "High-cost SQL ranked by a secondary resource or error dimension."
                if "throughput" in lower_title or "workload" in lower_title:
                        return "Aggregate workload throughput counters since last restart."
                if "configuration" in lower_title or "server config" in lower_title:
                        return "Key server configuration parameters affecting performance and durability."
                if "active sessions" in lower_title or "ash" in lower_title:
                        return "Current workload sample showing in-flight sessions, states, and SQL."
                if "section unavailable" in lower_content:
                        return "This section could not be collected on the target due to permissions or feature availability."
                return "Detailed engine telemetry captured for this diagnostic slice."

        overview_pairs = extract_key_value_pairs(sections[0][1]) if sections else []
        hero_metrics = overview_pairs[:4]
        section_count = len(sections)
        unavailable_count = report_text.lower().count("section unavailable")

        toc = []
        body = []
        for idx, (title, content) in enumerate(sections, start=1):
                anchor = f"sec-{idx}"
                toc.append(f"<li><a href='#{anchor}'>{html.escape(title)}</a></li>")
                rendered_blocks: list[str] = []
                for block_type, payload in parse_content_blocks(content):
                        if block_type == "text":
                                rendered_blocks.append(f"<pre>{html.escape(str(payload))}</pre>")
                        else:
                                headers, rows = payload  # type: ignore[misc]
                                head_html = "".join(f"<th>{html.escape(col)}</th>" for col in headers)
                                row_html = []
                                for row in rows:
                                        row_html.append("<tr>" + "".join(f"<td>{html.escape(cell)}</td>" for cell in row) + "</tr>")
                                rendered_blocks.append(
                                        "\n".join(
                                                [
                                                        "<div class='table-wrap'>",
                                                        "  <table>",
                                                        f"    <thead><tr>{head_html}</tr></thead>",
                                                        f"    <tbody>{''.join(row_html)}</tbody>",
                                                        "  </table>",
                                                        "</div>",
                                                ]
                                        )
                                )
                body.append(
                        "\n".join(
                                [
                                        f"<section id='{anchor}' class='card'>",
                                        f"  <div class='section-head'><h3>{html.escape(title)}</h3><p>{html.escape(summarize_section(title, content))}</p></div>",
                                        *rendered_blocks,
                                        "</section>",
                                ]
                        )
                )

        findings_html = "\n".join(f"<li>{html.escape(item)}</li>" for item in findings)

        return f"""<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>CPF AWR-Style Report - {html.escape(engine)}</title>
    <style>
        :root {{
                        --bg: #f4efe6;
                        --panel: #fffdf8;
                        --panel-strong: #fffaf0;
                        --fg: #172033;
                        --muted: #5f6476;
                        --border: #dfd3bf;
                        --accent: #92400e;
                        --accent-2: #0f766e;
                        --accent-3: #1d4ed8;
                        --shadow: 0 18px 40px rgba(23, 32, 51, 0.08);
        }}
                * {{ box-sizing: border-box; }}
                body {{ margin: 0; background: radial-gradient(circle at top left, #fff7e8 0, #f4efe6 45%, #ede5d7 100%); color: var(--fg); font-family: Segoe UI, Arial, sans-serif; }}
                .wrap {{ max-width: 1560px; margin: 0 auto; padding: 28px; }}
                .hero {{ background: linear-gradient(135deg, rgba(255, 250, 240, 0.96), rgba(243, 248, 255, 0.96)); border: 1px solid var(--border); border-radius: 22px; padding: 28px; box-shadow: var(--shadow); }}
                h1 {{ margin: 0 0 10px 0; font-size: 34px; line-height: 1.1; }}
                h3 {{ margin: 0; }}
                .meta {{ color: var(--muted); font-size: 13px; margin-top: 6px; }}
                .hero-grid {{ display: grid; grid-template-columns: 1.5fr 1fr; gap: 18px; align-items: start; }}
                .hero-copy p {{ margin: 12px 0 0 0; max-width: 70ch; color: var(--muted); line-height: 1.5; }}
                .metric-grid {{ display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }}
                .metric {{ background: rgba(255,255,255,0.7); border: 1px solid var(--border); border-radius: 16px; padding: 14px; }}
                .metric-label {{ color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.08em; }}
                .metric-value {{ margin-top: 6px; font-weight: 700; font-size: 18px; word-break: break-word; }}
                .summary-strip {{ display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; margin-top: 18px; }}
                .summary-card {{ background: var(--panel-strong); border: 1px solid var(--border); border-radius: 14px; padding: 14px; }}
                .summary-card strong {{ display: block; font-size: 24px; margin-top: 6px; }}
                .grid {{ display: grid; grid-template-columns: 320px 1fr; gap: 18px; margin-top: 18px; align-items: start; }}
                .card {{ background: var(--panel); border: 1px solid var(--border); border-radius: 18px; padding: 16px; margin-bottom: 16px; box-shadow: var(--shadow); }}
                .sidebar {{ position: sticky; top: 16px; }}
                .section-head {{ display: flex; justify-content: space-between; align-items: start; gap: 16px; margin-bottom: 14px; }}
                .section-head p {{ margin: 0; color: var(--muted); max-width: 70ch; line-height: 1.45; }}
                pre {{ margin: 0; white-space: pre-wrap; word-break: break-word; font-family: Consolas, 'Courier New', monospace; font-size: 12px; line-height: 1.45; background: #fff; border: 1px solid var(--border); border-radius: 12px; padding: 12px; }}
                ul {{ margin-top: 8px; padding-left: 18px; }}
                ol {{ margin: 0; padding-left: 20px; }}
                li {{ margin-bottom: 8px; }}
                a {{ color: var(--accent-3); text-decoration: none; }}
        a:hover {{ text-decoration: underline; }}
                .table-wrap {{ overflow-x: auto; border: 1px solid var(--border); border-radius: 14px; background: #fff; }}
                table {{ width: 100%; border-collapse: collapse; font-size: 12px; }}
                thead {{ position: sticky; top: 0; z-index: 1; }}
                th {{ background: #f8edd8; color: var(--fg); text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--border); white-space: nowrap; }}
                td {{ padding: 10px 12px; border-bottom: 1px solid #eee3d3; vertical-align: top; }}
                tbody tr:nth-child(even) {{ background: #fffaf1; }}
                .badge {{ display: inline-flex; align-items: center; gap: 6px; border-radius: 999px; padding: 6px 10px; font-size: 12px; background: #fef3c7; color: #92400e; border: 1px solid #f1d18a; margin-bottom: 10px; }}
                .muted {{ color: var(--muted); }}
                @media (max-width: 1180px) {{ .hero-grid, .grid, .summary-strip {{ grid-template-columns: 1fr; }} .sidebar {{ position: static; }} .metric-grid {{ grid-template-columns: 1fr 1fr; }} }}
                @media (max-width: 720px) {{ .wrap {{ padding: 16px; }} .metric-grid {{ grid-template-columns: 1fr; }} h1 {{ font-size: 28px; }} .section-head {{ display: block; }} .summary-strip {{ grid-template-columns: 1fr 1fr; }} }}
    </style>
</head>
<body>
    <div class="wrap">
        <div class="hero">
                        <div class="hero-grid">
                                <div class="hero-copy">
                                        <div class="badge">AWR / ASH analogue for {html.escape(engine)}</div>
                                        <h1>CPF Observability Performance Report</h1>
                                        <div class="meta">Generated at {html.escape(generated)} UTC</div>
                                        <div class="meta">Single-run deep diagnostic report with structured DMV, Query Store, IO, wait, memory, concurrency, and availability sections.</div>
                                        <p>This report is organized to resemble the operator flow of an AWR-style review: start with identity and configuration, move through wait and resource pressure, then inspect active workload, top SQL, contention, storage, and HA state.</p>
                                </div>
                                <div class="metric-grid">
                                        {''.join(f"<div class='metric'><div class='metric-label'>{html.escape(label)}</div><div class='metric-value'>{html.escape(value)}</div></div>" for label, value in hero_metrics) or "<div class='metric'><div class='metric-label'>Engine</div><div class='metric-value'>" + html.escape(engine) + "</div></div>"}
                                </div>
                        </div>
                        <div class="summary-strip">
                                <div class="summary-card"><span class="muted">Sections</span><strong>{section_count}</strong></div>
                                <div class="summary-card"><span class="muted">Auto Findings</span><strong>{len(findings)}</strong></div>
                                <div class="summary-card"><span class="muted">Unavailable Sections</span><strong>{unavailable_count}</strong></div>
                                <div class="summary-card"><span class="muted">Render Mode</span><strong>Structured HTML</strong></div>
                        </div>
        </div>

        <div class="grid">
                        <aside class="sidebar">
                <div class="card">
                    <h3>Auto Findings</h3>
                    <ul>
                        {findings_html}
                    </ul>
                </div>
                <div class="card">
                    <h3>Recommendations</h3>
                    <p>{html.escape(recommendation)}</p>
                </div>
                <div class="card">
                    <h3>Sections</h3>
                    <ol>
                        {''.join(toc)}
                    </ol>
                </div>
            </aside>
            <main>
                {''.join(body)}
            </main>
        </div>
    </div>
</body>
</html>
"""


def main() -> int:
        parser = argparse.ArgumentParser(description="Render CPF AWR-style HTML report from TXT input")
        parser.add_argument("--engine", required=True, help="Database engine name")
        parser.add_argument("--input", required=True, help="Input TXT report path")
        parser.add_argument("--output", required=True, help="Output HTML report path")
        args = parser.parse_args()

        src = Path(args.input)
        dst = Path(args.output)

        report_text = src.read_text(encoding="utf-8", errors="replace")
        sections = parse_sections(report_text)
        html_content = render_html(args.engine, report_text, sections)
        dst.write_text(html_content, encoding="utf-8")
        return 0


if __name__ == "__main__":
        raise SystemExit(main())

