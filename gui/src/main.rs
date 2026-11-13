// No console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use miti::{Bs, day_json, month_json};

// These return the same JSON as `miti today -j`, `miti month Y-M` and `miti ad2bs -j`; ui/index.html parses it.
#[tauri::command]
fn today() -> Result<String, String> {
    Bs::today().map(day_json).ok_or_else(|| "today is outside the date table".into())
}

#[tauri::command]
fn month(year: u16, month: u8) -> Result<String, String> {
    month_json(year, month).ok_or_else(|| format!("{year}-{month} is outside the date table"))
}

#[tauri::command]
fn ad2bs(year: i32, month: u8, day: u8) -> Result<String, String> {
    Bs::from_ad(year, month, day)
        .map(day_json)
        .ok_or_else(|| format!("no such AD date in table: {year}-{month}-{day}"))
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![today, month, ad2bs])
        .run(tauri::generate_context!())
        .expect("failed to run miti-gui");
}
