fn main() {
    #[cfg(windows)]
    {
        use std::io::Write;
        let mut res = winres::WindowsResource::new();
        res.set_icon("../../res/icon.ico")
            .set_language(winapi::um::winnt::MAKELANGID(
                winapi::um::winnt::LANG_ENGLISH,
                winapi::um::winnt::SUBLANG_ENGLISH_US,
            ))
            // Taesan: packer 는 순수 포터블 실행기(asInvoker)로 둔다. 관리자권한/설치는
            // 별도 표준 인스톨러(res/inno/taesan.iss)가 담당한다. res/manifest.xml 은
            // requestedExecutionLevel 이 없어 asInvoker 기본값.
            .set_manifest_file("../../res/manifest.xml");
        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}
