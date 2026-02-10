use std::{ffi::CString, ptr};

use libc::{c_char, c_int, c_void, size_t};

#[repr(C)]
struct sd_journal {
    _private: [u8; 0],
}

#[link(name = "systemd")]
unsafe extern "C" {
    fn sd_journal_open(j: *mut *mut sd_journal, i: c_int) -> c_int;
    // fn sd_journal_close(j: *mut sd_journal) -> c_int;

    // fn sd_journal_seek_tail(j: *mut sd_journal) -> c_int;

    // fn sd_journal_previous(j: *mut sd_journal) -> c_int;
    fn sd_journal_next(j: *mut sd_journal) -> c_int;
    fn sd_journal_wait(j: *mut sd_journal, timeout: u64) -> c_int;

    fn sd_journal_get_data(
        j: *mut sd_journal,
        field: *const c_char,
        data: *mut *const c_void,
        length: *mut size_t,
    ) -> c_int;
    // fn sd_journal_add_match(j: *mut sd_journal, data: *const c_void, size: size_t) -> c_int;
}

fn get_field(j: *mut sd_journal, key: &str) -> Option<&str> {
    let key = CString::new(key).unwrap();
    let mut data: *const c_void = ptr::null();
    let mut len: usize = 0;
    unsafe {
        if sd_journal_get_data(j, key.as_ptr(), &mut data, &mut len) < 0 {
            return None;
        }
        let slice = std::slice::from_raw_parts(data as *const u8, len);
        let s = std::str::from_utf8_unchecked(slice);
        s.split_once('=').map(|(_, v)| v)
    }
}

fn main() {
    unsafe {
        let mut journal: *mut sd_journal = ptr::null_mut();

        // Open local journal
        if sd_journal_open(&mut journal, 0) < 0 {
            panic!("failed to open journal");
        }

        // Move to end (tail -f behavior)
        // sd_journal_seek_tail(journal);
        sd_journal_next(journal);

        println!("listening for container logs…");

        loop {
            // Sleep until new entries arrive (ZERO CPU idle)
            sd_journal_wait(journal, u64::MAX);

            while sd_journal_next(journal) > 0 {
                // ---- container detection ----
                let container_id = match get_field(journal, "CONTAINER_ID_FULL") {
                    Some(v) => v,
                    None => continue, // skip non-container logs
                };

                let name = get_field(journal, "CONTAINER_NAME").unwrap_or("-");
                let msg = get_field(journal, "MESSAGE").unwrap_or("");

                println!("[container={} name={}] {}", container_id, name, msg);
            }
        }

        // never reached, but correct cleanup
    }
}
