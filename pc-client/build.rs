use std::path::{Path, PathBuf};
use std::process::Command;

fn find_rc_exe() -> Option<PathBuf> {
    // 1. Check if rc.exe is on PATH
    if let Ok(output) = Command::new("where.exe").arg("rc.exe").output() {
        if output.status.success() {
            let path_str = String::from_utf8_lossy(&output.stdout);
            if let Some(first_line) = path_str.lines().next() {
                let p = PathBuf::from(first_line.trim());
                if p.exists() {
                    return Some(p);
                }
            }
        }
    }

    // 2. Search Windows SDK installation paths
    let roots = [
        r"C:\Program Files (x86)\Windows Kits\10\bin",
        r"C:\Program Files\Windows Kits\10\bin",
    ];

    for root in &roots {
        let root_path = Path::new(root);
        if let Ok(entries) = std::fs::read_dir(root_path) {
            let mut versions: Vec<_> = entries
                .filter_map(|e| e.ok())
                .filter(|e| e.path().is_dir())
                .map(|e| e.path())
                .collect();
            // Sort to check newest SDK version first
            versions.sort_by(|a, b| b.cmp(a));

            for ver_dir in versions {
                let candidate = ver_dir.join("x64").join("rc.exe");
                if candidate.exists() {
                    return Some(candidate);
                }
            }
        }
    }

    None
}

fn main() {
    #[cfg(target_os = "windows")]
    {
        println!("cargo:rerun-if-changed=pouse.rc");
        println!("cargo:rerun-if-changed=assets/pouse.ico");
        println!("cargo:rerun-if-changed=assets/pouse-tray.ico");

        if let Some(rc_exe) = find_rc_exe() {
            let out_dir = std::env::var("OUT_DIR").unwrap_or_else(|_| ".".to_string());
            let res_path = Path::new(&out_dir).join("pouse.res");

            let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap_or_else(|_| ".".to_string());
            let rc_file = Path::new(&manifest_dir).join("pouse.rc");

            let status = Command::new(&rc_exe)
                .current_dir(&manifest_dir)
                .args(["/fo", res_path.to_str().unwrap(), rc_file.to_str().unwrap()])
                .status();

            if let Ok(s) = status {
                if s.success() {
                    println!("cargo:rustc-link-arg={}", res_path.display());
                    println!("cargo:warning=Embedded Windows resource and icon into binary via {}", rc_exe.display());
                } else {
                    println!("cargo:warning=rc.exe failed to compile pouse.rc");
                }
            }
        } else {
            println!("cargo:warning=rc.exe not found; skipping Windows resource embedding");
        }
    }
}
