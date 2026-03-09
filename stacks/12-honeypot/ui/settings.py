import time
import os
import zipfile
import datetime
import streamlit as st
from utils import load_settings, save_settings, BACKUP_DIR, CONFIG_PATH, restart_opencanary


def render_settings():
    settings = load_settings()
    creds = settings.get("credentials", {
        "username": "admin",
        "password": "admin",
        "capture_login": True
    })

    if st.session_state.get("layout") == "wide":
        st.session_state.layout = "centered"
        st.rerun()

    # ─── Capture login toggle ────────────────────────────────────────────────
    current = creds.get("capture_login", False)
    capture = st.checkbox("Capture login attempts in OpenCanary log", value=current, key="capture_login")
    if capture != current:
        creds["capture_login"] = capture
        settings["credentials"] = creds
        save_settings(settings)
        st.toast(f"capture_login set to {capture}")
        st.rerun()

    st.write("---")

    # ─── Password change ─────────────────────────────────────────────────────
    with st.form("password_form"):
        p1 = st.text_input("New password", type="password", key="p1")
        p2 = st.text_input("Confirm password", type="password", key="p2")
        col1, col2 = st.columns([3, 1])
        with col2:
            if st.form_submit_button("Update Password"):
                if p1 and p1 == p2:
                    creds["password"] = p1
                    settings["credentials"] = creds
                    save_settings(settings)
                    st.success("Password updated.")
                    time.sleep(2)
                    st.rerun()
                else:
                    st.error("Passwords must match")

    st.write("---")

    # ─── Config backup / restore ─────────────────────────────────────────────
    os.makedirs(BACKUP_DIR, exist_ok=True)

    col1, col2 = st.columns([3, 1])
    with col2:
        if st.button("Backup Config", use_container_width=True):
            ts = datetime.datetime.now().strftime("%Y%m%d-%H%M")
            backup_name = f"backup-{ts}.zip"
            backup_path = os.path.join(BACKUP_DIR, backup_name)
            with zipfile.ZipFile(backup_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                if os.path.exists(CONFIG_PATH):
                    zf.write(CONFIG_PATH, "opencanary.conf")
            st.success(f"Created backup: {backup_name}")
            time.sleep(2)
            st.rerun()

    with st.expander("Manage backups", expanded=False):
        backups = sorted(
            [f for f in os.listdir(BACKUP_DIR) if f.endswith(".zip")],
            reverse=True
        )
        for name in backups:
            col_name, col_dl, col_rs, col_del = st.columns([5, 1, 1, 1])
            path = os.path.join(BACKUP_DIR, name)
            with col_name:
                st.write(name)
            with col_dl:
                with open(path, "rb") as f:
                    st.download_button("⬇️", data=f, file_name=name,
                                       mime="application/zip", key=f"dl_{name}")
            with col_rs:
                if st.button("⟳", key=f"rs_{name}", help=f"Restore '{name}'"):
                    with zipfile.ZipFile(path, "r") as zf:
                        if "opencanary.conf" in zf.namelist():
                            os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
                            with zf.open("opencanary.conf") as src, open(CONFIG_PATH, "wb") as dst:
                                dst.write(src.read())
                    restart_opencanary()
                    st.success(f"Restored from {name}")
                    time.sleep(2)
                    st.rerun()
            with col_del:
                if st.button("❌", key=f"del_{name}", help=f"Delete '{name}'"):
                    os.remove(path)
                    st.success(f"Deleted backup: {name}")
                    time.sleep(2)
                    st.rerun()

        st.write("---")
        upload_col1, upload_col2 = st.columns([3, 1])
        with upload_col1:
            up = st.file_uploader("Upload backup (.zip)", type="zip", key="upload_backup")
        with upload_col2:
            st.markdown("<div style='height:40px;'></div>", unsafe_allow_html=True)
            if st.button("Upload", key="upload_backup_btn", use_container_width=True):
                if not up:
                    st.error("No file selected")
                else:
                    save_path = os.path.join(BACKUP_DIR, up.name)
                    with open(save_path, "wb") as f:
                        f.write(up.getbuffer())
                    st.success(f"Uploaded: {up.name}")
                    time.sleep(2)
                    st.rerun()

    st.write("---")

    # ─── Log viewer ─────────────────────────────────────────────────────────
    LOG_PATH = "/var/tmp/opencanary.log"
    with st.expander("OpenCanary log file", expanded=False):
        try:
            with open(LOG_PATH, "r", encoding="utf-8", errors="replace") as f:
                log_content = f.read()
        except FileNotFoundError:
            log_content = ""
            st.warning("Log file not found.")

        st.text_area("Log content", value=log_content, height=350, key="log_file_view", disabled=True)

    # ─── Footer ──────────────────────────────────────────────────────────────
    st.markdown("---")
    st.markdown(
        """
        <div style="text-align: center; padding-top: 20px;">
          <p>OpenCanary UI — adapted for Docker</p>
          <a href="https://github.com/chrisjbawden/opencanary-ui" target="_blank">
            <img src="https://cdn.jsdelivr.net/npm/@mdi/svg@6.9.96/svg/bird.svg" width="40"
                 style="filter: invert(29%) sepia(88%) saturate(6551%) hue-rotate(196deg)
                        brightness(92%) contrast(96%); display: block; margin: 0 auto 8px auto;"
                 alt="Bird icon"/>
            <div style="font-size: 0.9em;">Original project on GitHub</div>
          </a>
        </div>
        """,
        unsafe_allow_html=True,
    )
