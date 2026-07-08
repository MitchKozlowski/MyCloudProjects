"""
Main entry point: loads OHLCV data, runs a strategy, backtests it,
prints a report, and saves an equity curve chart.

Usage:
    python run_backtest.py --data data/BTCUSDT_1h.csv --strategy ema
    python run_backtest.py --data data/BTCUSDT_1h.csv --strategy rsi
"""

import argparse

import matplotlib.pyplot as plt
import pandas as pd

from backtest.engine import run_backtest, print_report, apply_stop_loss
from backtest.strategy import ema_crossover, rsi_mean_reversion, donchian_breakout


def plot_equity_curve(results: dict, strategy_name: str, out_path: str):
    df = results["df"]
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(11, 7), sharex=True, gridspec_kw={"height_ratios": [3, 1]})

    ax1.plot(df["open_time"], df["equity"], label=f"{strategy_name} strategy", linewidth=1.5)
    ax1.plot(df["open_time"], df["buy_hold_equity"], label="Buy & hold", linewidth=1, alpha=0.7)
    ax1.set_ylabel("Portfolio value ($)")
    ax1.legend()
    ax1.set_title(f"Backtest: {strategy_name}")
    ax1.grid(alpha=0.3)

    ax2.fill_between(df["open_time"], df["drawdown"] * 100, 0, color="firebrick", alpha=0.4)
    ax2.set_ylabel("Drawdown (%)")
    ax2.grid(alpha=0.3)

    plt.tight_layout()
    plt.savefig(out_path, dpi=120)
    print(f"Equity curve chart saved to {out_path}")


def main():
    parser = argparse.ArgumentParser(description="Backtest a crypto trading strategy")
    parser.add_argument("--data", required=True, help="Path to OHLCV CSV file")
    parser.add_argument("--strategy", choices=["ema", "rsi", "breakout"], default="ema")
    parser.add_argument("--fee", type=float, default=0.001, help="Round-trip fee per trade, e.g. 0.001 = 0.1%%")
    parser.add_argument("--capital", type=float, default=10_000, help="Starting capital")
    parser.add_argument("--out", default="equity_curve.png", help="Output chart path")

    # EMA-specific params
    parser.add_argument("--fast", type=int, default=12, help="EMA: fast period")
    parser.add_argument("--slow", type=int, default=26, help="EMA: slow period")

    # RSI-specific params
    parser.add_argument("--rsi-period", type=int, default=14, help="RSI: lookback period")
    parser.add_argument("--oversold", type=int, default=30, help="RSI: oversold threshold (buy below this)")
    parser.add_argument("--overbought", type=int, default=70, help="RSI: overbought threshold (sell above this)")

    # Breakout-specific params
    parser.add_argument("--entry-period", type=int, default=20, help="Breakout: bars to look back for entry high")
    parser.add_argument("--exit-period", type=int, default=10, help="Breakout: bars to look back for exit low")

    parser.add_argument("--stop-loss", type=float, default=None, help="Hard stop-loss from entry, e.g. 0.1 = exit at -10%%")
    parser.add_argument("--start", default=None, help="Filter data to this start date, e.g. 2022-01-01")
    parser.add_argument("--end", default=None, help="Filter data to this end date, e.g. 2022-12-31")

    args = parser.parse_args()

    df = pd.read_csv(args.data, parse_dates=["open_time"])

    if args.start:
        df = df[df["open_time"] >= pd.Timestamp(args.start, tz="UTC")]
    if args.end:
        df = df[df["open_time"] <= pd.Timestamp(args.end, tz="UTC")]
    df = df.reset_index(drop=True)

    if df.empty:
        raise SystemExit("No data left after applying --start/--end filters. Check your date range against the CSV's actual coverage.")

    date_range_label = f" [{df['open_time'].iloc[0].date()} to {df['open_time'].iloc[-1].date()}]"

    if args.strategy == "ema":
        df_with_signals = ema_crossover(df, fast=args.fast, slow=args.slow)
        strategy_label = f"EMA {args.fast}/{args.slow}"
    elif args.strategy == "breakout":
        df_with_signals = donchian_breakout(df, entry_period=args.entry_period, exit_period=args.exit_period)
        strategy_label = f"Breakout {args.entry_period}/{args.exit_period}"
    else:
        df_with_signals = rsi_mean_reversion(df, period=args.rsi_period, oversold=args.oversold, overbought=args.overbought)
        strategy_label = f"RSI {args.rsi_period} ({args.oversold}/{args.overbought})"

    if args.stop_loss is not None:
        df_with_signals = apply_stop_loss(df_with_signals, stop_loss_pct=args.stop_loss)
        strategy_label += f", {int(args.stop_loss * 100)}% stop-loss"

    strategy_label += date_range_label

    results = run_backtest(df_with_signals, fee_pct=args.fee, initial_capital=args.capital)
    print_report(results, strategy_name=strategy_label)
    plot_equity_curve(results, strategy_label, args.out)


if __name__ == "__main__":
    main()
