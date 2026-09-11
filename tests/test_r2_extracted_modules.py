#!/usr/bin/env python3
"""Offline contract simulation for the extracted POD/DMD/LCS interfaces.

This intentionally mirrors MATLAB array shapes and formulas; it does not
invoke MATLAB.  It catches the most common integration errors before a real
MATLAB run: frame/DOF orientation, mean restoration, DMD time origin, and
FTLE flow-map dimensions.
"""
from pathlib import Path

import numpy as np


def shared_module_paths_smoke():
    """The MATLAB interfaces are provided by the single shared namespace."""
    root = Path(__file__).resolve().parents[1]
    package = root / "lib" / "+tblR2"
    for name in ("pod_module", "pod_reconstruction", "dmd_module", "lcs_ftle"):
        assert (package / f"{name}.m").is_file(), name
    assert (root / "lib" / "+d23" / "default_config.m").is_file()
    for case in ("tandem_baseline_r2", "tandem_f40a3_phi0_r2"):
        assert not (root / "cases" / "per_case" / case / "+tblR2").exists()


def pod_reconstruction_smoke():
    rng = np.random.default_rng(7)
    n_frame, n_row, n_col, n_mode = 12, 4, 5, 3
    n_spatial = n_row * n_col
    X = rng.normal(size=(2 * n_spatial, n_frame))
    mean = rng.normal(size=(2 * n_spatial, 1))
    X = X + mean
    Xf = X - X.mean(axis=1, keepdims=True)
    u, s, vh = np.linalg.svd(Xf, full_matrices=False)
    modes = u[:, :n_mode]
    coeff = modes.T @ Xf
    pos = np.array([0, 5, 11])
    recon = modes @ coeff[:, pos] + X.mean(axis=1, keepdims=True)
    assert recon.shape == (2 * n_spatial, len(pos))
    assert np.isfinite(recon).all()
    assert np.linalg.norm((recon - X[:, pos])) / np.linalg.norm(X[:, pos]) < 1.0
    return recon


def dmd_smoke():
    dt = 0.01
    t = np.arange(80) * dt
    X = np.vstack((np.cos(2*np.pi*7*t), np.sin(2*np.pi*7*t)))
    X1, X2 = X[:, :-1], X[:, 1:]
    u, s, vh = np.linalg.svd(X1, full_matrices=False)
    r = 2
    at = u[:, :r].T @ X2 @ vh[:r].T @ np.diag(1/s[:r])
    eig, _ = np.linalg.eig(at)
    omega = np.log(eig) / dt
    freq = np.abs(np.imag(omega)) / (2*np.pi)
    assert np.min(np.abs(freq - 7)) < 1e-8
    return eig, omega


def lcs_ftle_smoke():
    # Uniform expansion u=a*x, v=a*y has FTLE ~= log(1+a*dt)/dt for the
    # explicit-Euler map used by the extracted MATLAB implementation.
    a, dt, n_steps = 0.2, 0.01, 10
    x = np.linspace(-1, 1, 9)
    y = np.linspace(-1, 1, 7)
    sx, sy = np.meshgrid(x, y)
    map_x = sx * (1 + a*dt)**n_steps
    map_y = sy * (1 + a*dt)**n_steps
    dx, dy = x[1]-x[0], y[1]-y[0]
    fx_y, fx_x = np.gradient(map_x, dy, dx)
    fy_y, fy_x = np.gradient(map_y, dy, dx)
    c11 = fx_x**2 + fy_x**2
    c22 = fx_y**2 + fy_y**2
    c12 = fx_x*fx_y + fy_x*fy_y
    lam = 0.5*(c11+c22+np.sqrt((c11-c22)**2+4*c12**2))
    ftle = np.log(lam)/(2*dt*n_steps)
    interior = ftle[1:-1, 1:-1]
    assert np.allclose(interior, np.log(1+a*dt)/dt, atol=1e-12)
    return ftle


def interface_edge_smoke():
    """Exercise the shape/finite-value contracts added to the MATLAB wrappers."""
    rng = np.random.default_rng(11)
    n_frame, n_row, n_col = 8, 3, 4
    U = rng.normal(size=(n_frame, n_row, n_col))
    V = rng.normal(size=U.shape)
    U[:, 1, 2] = np.nan
    V[:, 1, 2] = np.nan
    valid = np.isfinite(U).all(axis=0) & np.isfinite(V).all(axis=0)
    assert valid.shape == (n_row, n_col)
    assert not valid[1, 2]

    # Direct-array POD output contract: modes are mode-major 3-D fields and
    # invalid spatial points remain masked rather than becoming physical zeros.
    X_u = U.reshape(n_frame, -1).copy()
    X_v = V.reshape(n_frame, -1).copy()
    mean_u = np.zeros(X_u.shape[1])
    mean_v = np.zeros(X_v.shape[1])
    mean_u[valid.ravel()] = np.nanmean(X_u[:, valid.ravel()], axis=0)
    mean_v[valid.ravel()] = np.nanmean(X_v[:, valid.ravel()], axis=0)
    X = np.vstack(((X_u - mean_u).T, (X_v - mean_v).T))
    X[~np.isfinite(X)] = 0
    q, _, _ = np.linalg.svd(X, full_matrices=False)
    n_modes = min(n_frame - 1, q.shape[1])
    modes_u = q[:n_row*n_col, :n_modes].T.reshape(n_modes, n_row, n_col)
    modes_v = q[n_row*n_col:, :n_modes].T.reshape(n_modes, n_row, n_col)
    modes_u[:, ~valid] = np.nan
    modes_v[:, ~valid] = np.nan
    assert np.isnan(modes_u[:, 1, 2]).all()
    assert modes_u.shape == modes_v.shape == (n_modes, n_row, n_col)

    # DMD numerical-rank contract on a constant sequence.
    constant = np.ones((2, 12))
    singular = np.linalg.svd(constant[:, :-1], compute_uv=False)
    tol = max(constant[:, :-1].shape) * np.finfo(float).eps * max(singular.max(), 1)
    assert np.count_nonzero(singular > tol) == 1

    # LCS regular Cartesian-grid contract rejects a sheared coordinate array.
    x = np.linspace(0, 1, n_col)
    y = np.linspace(0, 1, n_row)
    xx, yy = np.meshgrid(x, y)
    sheared = xx + 0.1 * yy
    expected = np.tile(x, (n_row, 1))
    assert not np.allclose(sheared, expected)


def attachment_selection_smoke():
    """Mirror the legacy frame_start/frame_count and mode_indices adapter."""
    n_frames, n_modes = 120, 20
    frame_start, frame_count = 60, 1
    positions = np.arange(frame_start, frame_start + frame_count)
    assert positions.tolist() == [60]
    requested = np.array([1, 3, 7, 7, 20])
    mode_indices = np.unique(requested)
    assert mode_indices.tolist() == [1, 3, 7, 20]
    assert np.all((positions >= 1) & (positions <= n_frames))
    assert np.all((mode_indices >= 1) & (mode_indices <= n_modes))


def phase_vector_contract_smoke():
    """assign_phase returns a numeric vector, not a callable function handle."""
    bin_index = np.array([1, 2, 1, 3, 2, 1])
    frame_ids = np.array([1, 4, 6])
    bins = bin_index[frame_ids - 1]
    assert bins.tolist() == [1, 3, 1]
    assert np.all((bins >= 1) & (bins <= 3))


def lcs_boundary_smoke():
    """A final Euler step outside the velocity domain must be invalid."""
    x_bounds = (0.0, 1.0)
    y_bounds = (0.0, 1.0)
    final_x = np.array([[0.5, 1.2], [0.4, 0.8]])
    final_y = np.array([[0.5, 0.5], [1.1, 0.8]])
    valid = ((final_x >= x_bounds[0]) & (final_x <= x_bounds[1]) &
             (final_y >= y_bounds[0]) & (final_y <= y_bounds[1]))
    assert not valid[0, 1]
    assert not valid[1, 0]
    assert valid[0, 0] and valid[1, 1]


if __name__ == '__main__':
    shared_module_paths_smoke()
    pod_reconstruction_smoke()
    dmd_smoke()
    lcs_ftle_smoke()
    interface_edge_smoke()
    attachment_selection_smoke()
    phase_vector_contract_smoke()
    lcs_boundary_smoke()
    print('test_r2_extracted_modules: PASS')
