"""Schedule every minute, or run as a continuously supervised worker."""

import argparse
import asyncio

from starlette.concurrency import run_in_threadpool

from app.core.logging import get_logger
from app.core.monitoring import check_alerts, record_metric
from app.db.session import dispose_engine, get_session_factory, init_engine
from app.modules.media.cleanup import run_once


async def main(loop):
    init_engine()
    try:
        while True:
            try:
                async with get_session_factory()() as db:
                    await run_once(db)
            except Exception:
                get_logger("cleanup").error("cleanup.cycle_failed")
                try:
                    await run_in_threadpool(record_metric, "db_failure")
                    await run_in_threadpool(check_alerts)
                except Exception:
                    get_logger("cleanup").error("cleanup.alert_unavailable")
                if not loop:
                    raise
            if not loop:
                return
            await asyncio.sleep(60)
    finally:
        await dispose_engine()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--loop", action="store_true")
    asyncio.run(main(parser.parse_args().loop))
