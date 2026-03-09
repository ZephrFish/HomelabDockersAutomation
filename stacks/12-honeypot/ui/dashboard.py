import streamlit as st
import pandas as pd
import json
import altair as alt
import docker
from utils import read_text, LOG_PATH


def _container_status(name: str) -> str:
    try:
        client = docker.from_env()
        c = client.containers.get(name)
        return "✅" if c.status == "running" else "❌"
    except Exception:
        return "❌"


def render_dashboard():

    # ─── Service status indicators ─────────────────────────────────────────────
    st.write("**OpenCanary:**",        _container_status("opencanary"))
    st.write("**Alerter:**",           _container_status("opencanary-alerter"))
    st.write("**SMTP relay:**",        _container_status("opencanary-smtp"))

    # ─── Handle centered→wide one‑time rerun ────────────────────────────────────
    if st.session_state.get("layout") == "centered":
        st.session_state.layout = "wide"
        st.rerun()

    st.write("---")

    # ─── Load and parse logs ────────────────────────────────────────────────────
    raw = read_text(LOG_PATH)
    if not raw:
        return st.info(f"No logs at {LOG_PATH}")

    # ─── Filter bar + Search/Refresh ────────────────────────────────────────────
    col1, col2 = st.columns([4, 1])
    with col1:
        query = st.text_input(
            "Filter logs (use -substring to exclude)",
            value="-888 -1001",
            key="filter"
        )
    with col2:
        st.markdown('<div style="padding-top:27px;"></div>', unsafe_allow_html=True)
        if st.button("Search/Refresh", key="search_refresh", use_container_width=True):
            st.rerun()

    # ─── Filter parsing ─────────────────────────────────────────────────────────
    include_patterns = []
    exclude_patterns = []
    for part in query.split():
        if part.startswith("-") and len(part) > 1:
            exclude_patterns.append(part[1:].lower())
        elif part:
            include_patterns.append(part.lower())

    # ─── Entries for Graph (filtered) ───────────────────────────────────────────
    entries = []
    for line in raw.splitlines():
        text = line.lower()
        if include_patterns and not any(p in text for p in include_patterns):
            continue
        if any(e in text for e in exclude_patterns):
            continue
        try:
            obj = json.loads(line)
            ts = obj.get("local_time_adjusted")
            entries.append({
                "timestamp": pd.to_datetime(ts),
                "logtype": obj.get("logtype")
            })
        except (json.JSONDecodeError, TypeError, ValueError):
            continue

    now   = pd.Timestamp.now()
    start = now - pd.Timedelta(hours=6)
    df = pd.DataFrame(entries)

    if "timestamp" in df.columns:
        df = df[(df["timestamp"] >= start) & (df["timestamp"] <= now)]
    else:
        df = pd.DataFrame({"timestamp": [], "count": []})

    if not df.empty:
        df = (
            df
            .groupby(pd.Grouper(key="timestamp", freq="5min"))
            .size()
            .reset_index(name="count")
        )
        all_bins = pd.date_range(
            start=start.floor("5min"),
            end=now.ceil("5min"),
            freq="5min"
        )
        df = (
            df
            .set_index("timestamp")
            .reindex(all_bins, fill_value=0)
            .rename_axis("timestamp")
            .reset_index()
        )
    else:
        df = pd.DataFrame({"timestamp": [], "count": []})

    # ─── Chart ─────────────────────────────────────────────────────────────────
    with st.expander("Activity over last 6 hours", expanded=True):
        chart = (
            alt.Chart(df)
            .mark_line(point=True)
            .encode(
                x=alt.X("timestamp:T", axis=alt.Axis(title=None)),
                y=alt.Y("count:Q",    axis=alt.Axis(title=None)),
                tooltip=[
                    alt.Tooltip("timestamp", type="temporal",     title="Time"),
                    alt.Tooltip("count",     type="quantitative", title="Events"),
                ]
            )
            .properties(height=200)
        )
        st.altair_chart(chart, use_container_width=True)

    st.write("---")

    # ─── Log viewer ─────────────────────────────────────────────────────────────
    lines = []
    for l in raw.splitlines():
        text = l.lower()
        if include_patterns and not any(p in text for p in include_patterns):
            continue
        if any(e in text for e in exclude_patterns):
            continue
        lines.append(l)

    tail = lines[-200:] if len(lines) > 200 else lines
    tail.reverse()

    logs = []
    for line in tail:
        try:
            logs.append(json.loads(line))
        except json.JSONDecodeError:
            continue

    if "show_logs" not in st.session_state:
        st.session_state.show_logs = 10

    for entry in logs[: st.session_state.show_logs]:
        time_str = entry.get("local_time_adjusted", "")
        ltype    = entry.get("logtype", "")
        header   = f"{time_str} - [type {ltype}]"
        with st.expander(header):
            for key, val in entry.items():
                if key != "logdata":
                    st.write(f"**{key}**: {val}")
            if "logdata" in entry:
                st.write("**logdata**:")
                st.json(entry["logdata"])

    if len(logs) > st.session_state.show_logs:
        if st.button("Show more logs", key="show_more_logs_button", use_container_width=True):
            st.session_state.show_logs += 10
            st.rerun()
