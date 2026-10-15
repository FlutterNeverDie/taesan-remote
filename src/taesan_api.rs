//! 계정 기능(로그인·주소록 동기화)을 끈다. 이 빌드는 API 서버를 쓰지 않는다.
//!
//! `api-server` 가 비어 있으면 업스트림은 `https://admin.rustdesk.com` 으로 요청을 보낸다. 그래서 계정 기능을
//! 아예 끈다(HARD `disable-account` — 로그인·공유 주소록·그룹 탭이 사라진다). 주소록은 각 PC 의 로컬 주소록을 쓴다.

use hbb_common::config;

/// 프로세스마다 한 번 적용한다(`global_init`).
pub fn apply() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        config::HARD_SETTINGS
            .write()
            .unwrap()
            .insert("disable-account".to_owned(), "Y".to_owned());
    });
}

/// hbbs(접속 중계)로 보내는 접속 요청에 실을 로그인 토큰 — 항상 빈 값이다.
///
/// OSS hbbs 는 키 교환도 토큰도 쓰지 않는다. 토큰을 실으면 클라이언트가 키 교환 응답을 기다리다 접속이 실패한다.
pub fn rendezvous_token(_access_token: &str) -> &'static str {
    ""
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rendezvous_token_is_empty() {
        assert_eq!(rendezvous_token("some-access-token"), "");
    }

    #[test]
    fn test_apply_disables_account() {
        apply();
        assert!(config::is_disable_account());
    }
}
