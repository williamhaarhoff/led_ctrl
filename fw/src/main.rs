#![no_std]
#![no_main]

use defmt::*;
use defmt_rtt as _; // <- RTT logging
                    // use defmt_serial as _;
                    // use defmt_panic as _;
use embassy_executor::Spawner;
use embassy_stm32::gpio::{Level, Output, Speed};
use embassy_time::{Duration, Instant, Timer};
use panic_probe as _;

#[defmt::panic_handler]
fn panic() -> ! {
    cortex_m::asm::udf()
}

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    info!("🔌 Hello from Embassy STM32!");
    let p = embassy_stm32::init(Default::default());
    let mut led = Output::new(p.PA6, Level::Low, Speed::Low);
    let start = Instant::now();

    loop {
        let now = Instant::now();

        let mut ontime = Duration::from_micros(10);
        if (now - start).as_millis() % 100 == 0 {
            ontime = Duration::from_micros(50);
        }

        info!("🔆 LED on {:?}", ontime);
        led.set_high();
        Timer::after(ontime).await;

        info!("🌑 LED off");
        led.set_low();
        Timer::after(Duration::from_millis(1)).await;

        // After 4 hours turn off - this causes battery to shut off
        if now - start > Duration::from_secs(4 * 3600) {
            break;
        }
    }

    loop {
        info!("in auto turn off");
        Timer::after(Duration::from_secs(10)).await;
    }
}
