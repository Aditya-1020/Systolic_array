import pytest
from scripts.flow import build_parser, validate_tag

def test_short_stage_command():
    args = build_parser().parse_args(["synth", "--tag", "baseline"])
    assert args.command == "synth"
    assert args.tag == "baseline"

def test_run_stage_command():
    args = build_parser().parse_args(["run", "place", "--tag", "trial"])
    assert args.command == "run"
    assert args.stage == "place"
    assert args.tag == "trial"

@pytest.mark.parametrize("tag", ["../outside", ".", "..", "a/b", "white space", ""])
def test_reject_invalid_tag(tag):
    with pytest.raises(ValueError):
        validate_tag(tag)

def test_accept_tag():
    assert validate_tag("baseline_01") == "baseline_01"
