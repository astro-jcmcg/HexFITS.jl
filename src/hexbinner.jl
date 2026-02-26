module hexbinner

using FITSFiles, Statistics

export hexbin

### gridsize is calculated based on image and beam sizes
function find_gridsize(header)
    image_length = header["NAXIS1"] * header["CDELT2"]
    image_beam_a = (π * header["BMAJ"] * header["BMIN"]) / (4 * log(2))
    hex_width = sqrt((2 * image_beam_a) / sqrt(3))
    return Int(ceil(image_length / hex_width))
end

### generate hexagonal binning based on matplotlib.hexbin
function hex_geometry(nx_pixels, ny_pixels, gridsize)

    nx_hex = gridsize
    ny_hex = Int(floor(nx_hex / sqrt(3)))

    xmin, xmax = 0.0, nx_pixels
    ymin, ymax = 0.0, ny_pixels

    padding = 1e-9 * (xmax - xmin)
    xmin -= padding
    xmax += padding

    sx = (xmax - xmin) / nx_hex
    sy = (ymax - ymin) / ny_hex

    return xmin, ymin, sx, sy, nx_hex, ny_hex
end

function compute_hex_values(image, gridsize)

    ny, nx = size(image)

    xmin, ymin, sx, sy, nx_hex, ny_hex =
        hex_geometry(nx, ny, gridsize)

    nx1, ny1 = nx_hex + 1, ny_hex + 1
    nx2, ny2 = nx_hex, ny_hex

    n_primary = nx1 * ny1
    n_secondary = nx2 * ny2

    bins = [Float64[] for _ in 1:(n_primary+n_secondary)]

    for row in 1:ny
        for col in 1:nx

            val = image[row, col]
            if !isfinite(val)
                continue
            end

            x = col - 1
            y = row - 1

            ix = (x - xmin) / sx
            iy = (y - ymin) / sy

            ix1 = round(Int, ix)
            iy1 = round(Int, iy)

            ix2 = floor(Int, ix)
            iy2 = floor(Int, iy)

            d1 = (ix - ix1)^2 + 3 * (iy - iy1)^2
            d2 = (ix - ix2 - 0.5)^2 + 3 * (iy - iy2 - 0.5)^2

            if d1 < d2
                if 0 ≤ ix1 < nx1 && 0 ≤ iy1 < ny1
                    idx = ix1 * ny1 + iy1 + 1
                    push!(bins[idx], val)
                end
            else
                if 0 ≤ ix2 < nx2 && 0 ≤ iy2 < ny2
                    idx = n_primary + ix2 * ny2 + iy2 + 1
                    push!(bins[idx], val)
                end
            end
        end
    end

    values = [isempty(b) ? NaN : mean(b) for b in bins]

    return values, nx_hex, ny_hex
end

function hex_fill_image(image, gridsize)

    ny, nx = size(image)

    values, nx_hex, ny_hex = compute_hex_values(image, gridsize)

    xmin, ymin, sx, sy, _, _ =
        hex_geometry(nx, ny, gridsize)

    nx1, ny1 = nx_hex + 1, ny_hex + 1
    nx2, ny2 = nx_hex, ny_hex
    n_primary = nx1 * ny1

    output = fill(NaN, ny, nx)

    for row in 1:ny
        for col in 1:nx

            x = col - 1
            y = row - 1

            ix = (x - xmin) / sx
            iy = (y - ymin) / sy

            ix1 = round(Int, ix)
            iy1 = round(Int, iy)

            ix2 = floor(Int, ix)
            iy2 = floor(Int, iy)

            d1 = (ix - ix1)^2 + 3 * (iy - iy1)^2
            d2 = (ix - ix2 - 0.5)^2 + 3 * (iy - iy2 - 0.5)^2

            if d1 < d2
                if 0 ≤ ix1 < nx1 && 0 ≤ iy1 < ny1
                    idx = ix1 * ny1 + iy1 + 1
                    output[row, col] = values[idx]
                end
            else
                if 0 ≤ ix2 < nx2 && 0 ≤ iy2 < ny2
                    idx = n_primary + ix2 * ny2 + iy2 + 1
                    output[row, col] = values[idx]
                end
            end
        end
    end

    return output
end

### user facing function
function hexbin(input_file::String; output_suffix="-hexbin")

    hdus = fits(input_file)

    header = hdus[1].cards
    rawimage = hdus[1].data

    # CASA produced images usually 4D, not intrested in freq or stokes
    image = rawimage[:, :, 1, 1]

    gridsize = find_gridsize(header)
    hex_image = hex_fill_image(image, gridsize)
    hdus[1] = FITSFiles.HDU(hex_image, header)
    output_file = replace(input_file, ".fits" => "$(output_suffix).fits")
    FITSFiles.write(output_file, hdus)
    println("Wrote ", output_file)

    return output_file
end

end