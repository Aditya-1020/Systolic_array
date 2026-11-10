
import argparse
import csv
from pathlib import Path

from openroad import Design, Tech


MACROS = {
    "u_rbuf_mem.g_256x64.u_mem": "rbuf",
    "u_abuf_mem.g_64x64.u_mem": "small",
    "u_wbuf_mem.g_64x64.u_mem": "small",
}


def transform_bbox(mx, my, width, lx1, ly1, lx2, ly2, orientation):
    if orientation == "R0":
        gx1 = mx + lx1
        gx2 = mx + lx2
        gy1 = my + ly1
        gy2 = my + ly2

    elif orientation == "MY":
        gx1 = mx + width - lx2
        gx2 = mx + width - lx1
        gy1 = my + ly1
        gy2 = my + ly2

    else:
        raise ValueError(f"Unsupported orientation: {orientation}")

    return gx1, gy1, gx2, gy2


def get_orientation(inst):
    orient = inst.getOrient()
    return orient.getString()


def get_location(inst):
    point = inst.getLocation()
    return point.x(), point.y()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--odb", required=True)
    parser.add_argument("--rbuf-csv", required=True)
    parser.add_argument("--small-csv", required=True)
    parser.add_argument("--out", default="macro_pinmap.csv")
    args = parser.parse_args()

    tech = Tech()
    design = Design(tech)
    design.readDb(args.odb)

    block = design.getBlock()
    dbu = block.getDbUnitsPerMicron()

    csv_files = {
        "rbuf": args.rbuf_csv,
        "small": args.small_csv,
    }

    output = []

    for inst_name, csv_key in MACROS.items():
        inst = block.findInst(inst_name)

        if inst is None:
            raise RuntimeError(f"Instance not found: {inst_name}")

        master = inst.getMaster()
        orientation = get_orientation(inst)

        x, y = get_location(inst)

        mx = x / dbu
        my = y / dbu

        width = master.getWidth() / dbu
        height = master.getHeight() / dbu

        print(
            f"{inst_name}: "
            f"location=({mx:.3f}, {my:.3f}) "
            f"size=({width:.3f}, {height:.3f}) "
            f"orientation={orientation}"
        )

        with open(csv_files[csv_key], newline="") as file:
            reader = csv.DictReader(file)

            for row in reader:
                lx1 = float(row["rect_x1"])
                ly1 = float(row["rect_y1"])
                lx2 = float(row["rect_x2"])
                ly2 = float(row["rect_y2"])

                gx1, gy1, gx2, gy2 = transform_bbox(
                    mx, my, width,
                    lx1, ly1, lx2, ly2,
                    orientation
                )

                output.append({
                    "instance": inst_name,
                    "pin": row["pin"],
                    "direction": row["direction"],
                    "port": row["port"],
                    "layer": row["layer"],
                    "orientation": orientation,
                    "global_x1": gx1,
                    "global_y1": gy1,
                    "global_x2": gx2,
                    "global_y2": gy2,
                })

    output_path = Path(args.out)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("w", newline="") as file:
        writer = csv.DictWriter(
            file,
            fieldnames=output[0].keys()
        )
        writer.writeheader()
        writer.writerows(output)

    print(f"\nExported {len(output)} pin shapes to {output_path}")


if __name__ == "__main__":
    main()
