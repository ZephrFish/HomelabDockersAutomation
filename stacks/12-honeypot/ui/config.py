import streamlit as st
import json
import uuid
import time

from utils import (
    load_json, save_json, restart_opencanary,
    CONFIG_PATH,
    get_setting, set_setting
)

FTP_BANNERS = [
    "FileZilla Server 0.9",
    "Disk Station FTP server at DiskStation ready.",
    "Microsoft FTP Service",
    "(vsFTPd 3.0.3)"
]
SSH_VERSIONS = [
    "SSH-2.0-OpenSSH_5.1p1 Debian-4",
    "SSH-2.0-OpenSSH_7.4",
    "SSH-2.0-OpenSSH_8.0",
    "SSH-2.0-OpenSSH_6.8p1-hpn14v6"
]


def render_config():
    cfg = load_json(CONFIG_PATH)

    if st.session_state.get("layout") == "wide":
        st.session_state.layout = "centered"
        st.rerun()

    raw_mode = st.toggle("raw JSON config", value=False, key="cfg_raw_mode")

    if raw_mode:
        st.text_area(
            "Raw JSON Configuration",
            value=json.dumps(cfg, indent=2),
            height=500,
            key="cfg_raw_json",
        )
        if st.button("Save Raw Config"):
            try:
                new_cfg = json.loads(st.session_state.cfg_raw_json)
                save_json(CONFIG_PATH, new_cfg)
                restart_opencanary()
                st.success("Raw configuration saved & container restarted.")
                time.sleep(2)
                st.rerun()
            except json.JSONDecodeError as e:
                st.error(f"Invalid JSON: {e}")
        return

    initial = {
        "http.enabled":              cfg.get("http.enabled", False),
        "http.skin":                 cfg.get("http.skin", "nasLogin"),
        "http.port":                 cfg.get("http.port", 8880),
        "https.port":                cfg.get("https.port", 8843),
        "portscan.enabled":          cfg.get("portscan.enabled", False),
        "portscan.ignore_localhost": cfg.get("portscan.ignore_localhost", False),
        "ftp.port":                  cfg.get("ftp.port", None),
        "ftp.banner":                cfg.get("ftp.banner", FTP_BANNERS[0]),
        "ssh.enabled":               cfg.get("ssh.enabled", False),
        "ssh.port":                  cfg.get("ssh.port", 2223),
        "ssh.version":               cfg.get("ssh.version", SSH_VERSIONS[0]),
        "rdp.enabled":               cfg.get("rdp.enabled", False),
        "mysql.enabled":             cfg.get("mysql.enabled", False),
        "mssql.enabled":             cfg.get("mssql.enabled", False),
        "vnc.enabled":               cfg.get("vnc.enabled", False),
        "telnet.enabled":            cfg.get("telnet.enabled", False),
    }

    # ─── Device Node ID ──────────────────────────────────────────────────────
    device_node_id = cfg.get("device.node_id", "opencanary-1")
    new_node_id = st.text_input("Device Node ID", value=device_node_id, key="cfg_node_id")

    # ─── IP Ignorelist ───────────────────────────────────────────────────────
    st.markdown("**IP Ignorelist**")

    def as_dict_list(lst):
        if lst and isinstance(lst[0], dict):
            return lst
        return [{"id": str(uuid.uuid4()), "ip": ip} for ip in lst]

    if "ip_ignorelist_edit" not in st.session_state:
        st.session_state.ip_ignorelist_edit = as_dict_list(cfg.get("ip.ignorelist", []))

    ip_ignorelist_edit = st.session_state.ip_ignorelist_edit
    indices_to_remove = []
    for idx, entry in enumerate(ip_ignorelist_edit):
        col1, col2 = st.columns([8, 1])
        ip_value = col1.text_input("IP:", value=entry["ip"], key=f"ip_ignore_edit_{entry['id']}", label_visibility="collapsed")
        if ip_value != entry["ip"]:
            ip_ignorelist_edit[idx]["ip"] = ip_value
        with col2:
            st.markdown('<div style="margin-top: 27px;"></div>', unsafe_allow_html=True)
            if st.button("❌", key=f"del_ip_ignore_{entry['id']}", help="Remove this IP"):
                indices_to_remove.append(idx)

    for idx in reversed(indices_to_remove):
        ip_ignorelist_edit.pop(idx)
        st.rerun()

    if st.button("➕", key="add_ip_ignore_btn"):
        ip_ignorelist_edit.append({"id": str(uuid.uuid4()), "ip": ""})
        st.rerun()

    # ─── Services ─────────────────────────────────────────────────────────────
    st.markdown("---")
    st.markdown("**Services**")

    http_enabled  = st.checkbox("Enable HTTP/S",         value=initial["http.enabled"],   key="cfg_http_en")
    ssh_enabled   = st.checkbox("Enable SSH honeypot",   value=initial["ssh.enabled"],    key="cfg_ssh_en")
    ftp_enabled   = st.checkbox("Enable FTP honeypot",   value=initial["ftp.port"] is not None, key="cfg_ftp_en")
    rdp_enabled   = st.checkbox("Enable RDP honeypot",   value=initial["rdp.enabled"],    key="cfg_rdp_en")
    mysql_enabled = st.checkbox("Enable MySQL honeypot", value=initial["mysql.enabled"],  key="cfg_mysql_en")
    mssql_enabled = st.checkbox("Enable MSSQL honeypot", value=initial["mssql.enabled"],  key="cfg_mssql_en")
    vnc_enabled   = st.checkbox("Enable VNC honeypot",   value=initial["vnc.enabled"],    key="cfg_vnc_en")
    telnet_enabled = st.checkbox("Enable Telnet honeypot", value=initial["telnet.enabled"], key="cfg_telnet_en")
    ps_enabled    = st.checkbox("Enable portscan detection", value=initial["portscan.enabled"], key="cfg_ps_en")

    if http_enabled:
        col_http, col_https = st.columns(2)
        with col_http:
            st.number_input("HTTP port",  min_value=1, max_value=65535, value=initial["http.port"],  key="cfg_http_port")
        with col_https:
            st.number_input("HTTPS port", min_value=1, max_value=65535, value=initial["https.port"], key="cfg_https_port")

    if ssh_enabled:
        st.number_input("SSH port", min_value=1, max_value=65535, value=initial["ssh.port"], key="cfg_ssh_port")
        st.selectbox("SSH version", options=SSH_VERSIONS,
                     index=SSH_VERSIONS.index(initial["ssh.version"]) if initial["ssh.version"] in SSH_VERSIONS else 0,
                     key="cfg_ssh_ver")

    if ftp_enabled:
        st.number_input("FTP port", min_value=1, max_value=65535, value=initial["ftp.port"] or 21, key="cfg_ftp_port")
        banner_default = initial["ftp.banner"] if initial["ftp.banner"] in FTP_BANNERS else FTP_BANNERS[0]
        st.selectbox("FTP banner", options=FTP_BANNERS,
                     index=FTP_BANNERS.index(banner_default), key="cfg_ftp_banner")

    # ─── Save & Restart ───────────────────────────────────────────────────────
    st.markdown("---")
    if st.button("Save & Restart OpenCanary", use_container_width=True):
        cfg["device.node_id"] = st.session_state.cfg_node_id
        cfg["ip.ignorelist"] = [
            e["ip"].strip() for e in st.session_state.ip_ignorelist_edit if e["ip"].strip()
        ]

        cfg["http.enabled"]  = http_enabled
        cfg["https.enabled"] = http_enabled
        if http_enabled:
            cfg["http.port"]  = st.session_state.cfg_http_port
            cfg["https.port"] = st.session_state.cfg_https_port

        cfg["ssh.enabled"] = ssh_enabled
        if ssh_enabled:
            cfg["ssh.port"]    = st.session_state.cfg_ssh_port
            cfg["ssh.version"] = st.session_state.cfg_ssh_ver

        cfg["ftp.enabled"] = ftp_enabled
        if ftp_enabled:
            cfg["ftp.port"]   = st.session_state.cfg_ftp_port
            cfg["ftp.banner"] = st.session_state.cfg_ftp_banner
        else:
            cfg.pop("ftp.port", None)

        cfg["rdp.enabled"]    = rdp_enabled
        cfg["mysql.enabled"]  = mysql_enabled
        cfg["mssql.enabled"]  = mssql_enabled
        cfg["vnc.enabled"]    = vnc_enabled
        cfg["telnet.enabled"] = telnet_enabled
        cfg["portscan.enabled"] = ps_enabled

        save_json(CONFIG_PATH, cfg)
        restart_opencanary()
        st.success("Configuration saved & OpenCanary restarted.")
        time.sleep(2)
        st.rerun()
