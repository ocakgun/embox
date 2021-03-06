function Z=mkzmat(wg, mesh)
% Z=mkzmat(wg, mesh)
% Populates the impedance/reactions matrix
%
% wg     - shiedling parameters, see wgparams
% mesh   - meshed metal, see mkmesh
% 
 
% Upper limits of the waveguide mode orders to be used when evaluating
% the matrix elements: T(E/M)[0..M-1][0..N-1] modes are used. 
maxm=wg.nx*wg.cnx;
maxn=wg.ny*wg.cny;

% angular frequency
freq=wg.freq;

a=wg.a; % x-size of the waveguide
b=wg.b; % y-size of the waveguide
h=wg.h; % thickness of the layers

% Layers stackup, from bottom to top along z
weps = wg.weps;
wmu  = wg.wmu;

% wavenumbers of the layers
k=freq*sqrt(weps.*wmu);

% wm(m,n)=m-1, wn(m,n)=n-1
[ wm, wn ] = ndgrid(0:maxm-1, 0:maxn-1);

% x and y wavenumbers of the waveguide mode
kx = wm*pi./a;
ky = wn*pi./b;

% cutoff wavenumber of the waveguide geometry squared
kc2 = kx.^2+ky.^2;

% number of layers/sections
nl = length(weps);

% temporary, used below
k2mnl = repmat(reshape(k.^2,1,1,nl),maxm,maxn);
kc2mnl = repmat(kc2, [ 1 1 nl ]);

% waveguide layers/sections wavenumbers 
kz = sqrt(k2mnl - kc2mnl);

% Non-propagating wavenumbers for the loss-free case
kznp = sqrt(-k2mnl+kc2mnl)./j;
kz(find(real(k2mnl)<kc2mnl)) = kznp(find(real(k2mnl)<kc2mnl));

% waveguide layers/sections propagation constants
gamma = j*kz;

% clean up memory
clear k2mnl kc2mnl kz kznp wm wn

% Characteristic admittances of the TE modes
Y0e=gamma./(j*freq*repmat(shiftdim(wmu(:), -2), maxm, maxn));

% Characteristic admittances of the TM modes
Y0m=(j*freq*repmat(shiftdim(weps(:), -2), maxm, maxn))./gamma;

% normalization coefficients for te and tm waveguide modes
[ Ne, Nm ] = wnorm(a, b, maxm, maxn);

% They are only used squared
Ne2 = Ne.*Ne;
Nm2 = Nm.*Nm;

% layers/tlines endpoints coordinates
z=cumsum(h); 

% Prepare inputs for the tlines calculators - one for te and one for
% tm modes. The reshaping is needed because the calculator only allows
% one dimension for the tline parameters.
ztlc = reshape(repmat(shiftdim([ 0 ; z(:) ], -2), maxm, maxn), [], nl+1);
ktlc = reshape(gamma, [], nl);
tle=calc_tlines(ztlc, reshape(1./Y0e, [], nl), ktlc, wg.Gls0, wg.Ggr0);
tlm=calc_tlines(ztlc, reshape(1./Y0m, [], nl), ktlc, wg.Gls0, wg.Ggr0);

% clean up memory
clear Y0e Y0m gamma ztlc ktlc Ne Nm

% mesh cell sizes
dx=wg.a/wg.nx;
dy=wg.b/wg.ny;

% Multiplier resulting from x-integration of the triangular basis function
Gdx_tri=gtri(dx,kx);

% Multiplier resulting from x-integration of the constant (rectangular) b.f.
Gdx_flat=gflat(dx,kx);

% Multiplier resulting from y-integration of the triangular b.f.
Gdy_tri=gtri(dy,ky);

% Multiplier resulting from y-integration of the constant (rectangular) b.f.
Gdy_flat=gflat(dy,ky);

% The via basis function is scaled - such the that via current is equal to
% the x-directed basis function current - to adjust magnitudes of the Z 
% matrix elements involving via testing or/and source and thus improve
% conditioning of Z matrix.
viac = 1/dx;

% To shorten some expressions
viac2 = viac * viac;

% We want to pre-allocate the Z matrix, for that we need to know its size.
% To calculate the size we need to count the basis functions on all layers.
numx = sum(cellfun(@(v) length(v), { mesh.layers(:).xi }));
numy = sum(cellfun(@(v) length(v), { mesh.layers(:).yi }));
numv = sum(cellfun(@(v) length(v), { mesh.layers(:).vi }));
numbf = numx + numy + numv;

% We also compute the cumulative sums of numbers of the basis functions in
% the layers up to the given one which is then used to place the blocks
% of the matrix (see below)
cumx = cumsum(cellfun(@(v) length(v), { mesh.layers(:).xi }));
cumy = cumsum(cellfun(@(v) length(v), { mesh.layers(:).yi }));
cumv = cumsum(cellfun(@(v) length(v), { mesh.layers(:).vi }));
cumbf = [ 0 (cumx + cumy + cumv) ];

% Pre-allocate it!
Z = zeros(numbf); % can do complex(zeros(numbf)), but does it make sense?

% Here we start popolating the impedance matrix. The geometry consists of a
% number of layers of metallization (vias are on their way) and the Z matrix
% consists of N-by-N blocks where N is the number of layers. The block M(m,n)
% corresponds to the m-th observation and n-th source layer.
for mli = 1:length(mesh.layers)

    mlay = mesh.layers(mli);

    % Position of the m-th layer in the stackup
    mpos = mlay.pos;

    for nli = 1:length(mesh.layers)

	nlay = mesh.layers(nli);

	% Position of the n-th layer in the stackup
	npos = nlay.pos;

	% The waveguide modes are described in terms of equivalent transmission
	% lines, and here we compute the mutual impedance (or just the impedance
	% if source and observation layers coincide) which if multiplied by
	% the current source at the source layer position gives the voltage at
	% the observation layer. We call the tlines calculator (which we set up
	% earlier) to obtain the impedance.
	Ze = reshape(calc_vi(tle, z(mpos), mpos, z(npos), npos), maxm, maxn);
	Zm = reshape(calc_vi(tlm, z(mpos), mpos, z(npos), npos), maxm, maxn);

	% x-directed testing, x-directed source
        if numel(mlay.xi) && numel(nlay.xi)

	    Gxx=Gdx_tri.*Gdx_tri.*Gdy_flat.*Gdy_flat.*(-Ne2.*ky.*ky.*Ze-Nm2.*kx.*kx.*Zm);

	    [ cc, ss ] = myfft(Gxx);

	    [ mxi, nxi ] = ndgrid(mlay.xi, nlay.xi);
	    [ mxj, nxj ] = ndgrid(mlay.xj, nlay.xj);

	    idif = wrapidx((mxi-nxi)*wg.cnx/2+1, size(Gxx, 1));   % xt-xs
	    isum = wrapidx((mxi+nxi)*wg.cnx/2+1, size(Gxx, 1));   % xt+xs
	    jdif = wrapidx((mxj-nxj)*wg.cny/2+1, size(Gxx, 2));   % yt-ys
	    jsum = wrapidx((mxj+nxj+1)*wg.cny/2+1, size(Gxx, 2)); % yt+ys
	    % notice one is added to mxj+nxj when computing jsum - y-center of
	    % the x-directed basis is found as j*dy+dy/2, (j is the mesh index)
	    % the two halves added together give one

	    idif_jdif = sub2ind(size(cc), idif, jdif);
	    idif_jsum = sub2ind(size(cc), idif, jsum);
	    isum_jdif = sub2ind(size(cc), isum, jdif);
	    isum_jsum = sub2ind(size(cc), isum, jsum);

	    Zxx = (cc(idif_jdif) - cc(idif_jsum) + cc(isum_jdif) - cc(isum_jsum)) ./ 4;

	    % clean up memory
	    clear Gxx cc ss mxi nxi mxj nxj
	    clear idif isum jdif jsum idif_jdif idif_jsum isum_jdif isum_jsum

        else

	    Zxx = zeros(numel(mlay.xi), numel(nlay.xi));

        end

	% y-directed testing, x-directed source
        if numel(mlay.yi) && numel(nlay.xi)

	    Gyx=Gdx_tri.*Gdy_flat.*Gdx_flat.*Gdy_tri.*(Ne2.*ky.*kx.*Ze-Nm2.*kx.*ky.*Zm);

	    [ cc, ss ] = myfft(Gyx);

	    [ myi, nxi ] = ndgrid(mlay.yi, nlay.xi);
	    [ myj, nxj ] = ndgrid(mlay.yj, nlay.xj);

	    % y-position of x-directed bases (and x-position of y-directed) is the
	    % bottom/left edge (one with minimal x/y) - that is the reason for adding
	    % or subtracting wg.cnx/4 or wg.cny/4 (which corresponds to half-cell)
	    % Here for Zyx:
	    %  xt=myi*dx+dx/2 (y-directed testing)
	    %  ys=nxj*dy+dy/2 (x-directed source)
	    idif = wrapidx((myi-nxi)*wg.cnx/2 + wg.cnx/4 + 1, size(Gyx, 1)); % xt-xs
	    isum = wrapidx((myi+nxi)*wg.cnx/2 + wg.cnx/4 + 1, size(Gyx, 1)); % xt+xs
	    jdif = wrapidx((myj-nxj)*wg.cny/2 - wg.cny/4 + 1, size(Gyx, 2)); % yt-ys
	    jsum = wrapidx((myj+nxj)*wg.cny/2 + wg.cny/4 + 1, size(Gyx, 2)); % yt+ys

	    idif_jdif = sub2ind(size(ss), idif, jdif);
	    idif_jsum = sub2ind(size(ss), idif, jsum);
	    isum_jdif = sub2ind(size(ss), isum, jdif);
	    isum_jsum = sub2ind(size(ss), isum, jsum);

	    Zyx = (ss(isum_jsum) - ss(isum_jdif) + ss(idif_jsum) - ss(idif_jdif)) ./ 4;

	    % clean up memory
	    clear Gyx cc ss myi nxi myj nxj
	    clear idif isum jdif jsum idif_jdif idif_jsum isum_jdif isum_jsum

        else

	    Zyx = zeros(numel(mlay.yi), numel(nlay.xi));

        end

        % Integral of current over the via from the current source of horizontal
        % segment
	iii = reshape(calc_iii(tlm, mpos, z(npos), npos), maxm, maxn);

	% z-directed (via) testing, x-directed source
        if numel(mlay.vi) && numel(nlay.xi)

	    m = kc2./(j*freq*weps(mpos));
	    Gvx = Nm2.*kx.*Gdx_tri.*Gdy_flat.*Gdx_flat.*Gdy_flat.*m.*iii;

	    [ cc, ss, cs, sc ] = myfft(Gvx);

	    [ mvi, nxi ] = ndgrid(mlay.vi, nlay.xi);
	    [ mvj, nxj ] = ndgrid(mlay.vj, nlay.xj);

	    % y-position of x-directed bases (and x-position of y-directed) is the
	    % bottom/left edge (one with minimal x/y), x- and y-positions of the
	    % via is the bottom left corner (with minimal x/y) - that is the reason
	    % for adding or subtracting wg.cnx/4 or wg.cny/4 (which corresponds to
	    % half-cell)
	    % Here for Zvx:
	    %  xt=mvi*dx+dx/2 (z-directed (via) testing)
	    %  yt=mvj*dy+dy/2 (z-directed (via) testing)
	    %  ys=nxj*dy+dy/2 (x-directed source)
	    idif = wrapidx((mvi-nxi)*wg.cnx/2 + wg.cnx/4 + 1, size(Gvx, 1)); % xt-xs
	    isum = wrapidx((mvi+nxi)*wg.cnx/2 + wg.cnx/4 + 1, size(Gvx, 1)); % xt+xs
	    jdif = wrapidx((mvj-nxj)*wg.cny/2            + 1, size(Gvx, 2)); % yt-ys
	    jsum = wrapidx((mvj+nxj)*wg.cny/2 + wg.cny/2 + 1, size(Gvx, 2)); % yt+ys

	    idif_jdif = sub2ind(size(sc), idif, jdif);
	    idif_jsum = sub2ind(size(sc), idif, jsum);
	    isum_jdif = sub2ind(size(sc), isum, jdif);
	    isum_jsum = sub2ind(size(sc), isum, jsum);

	    Zvx = viac * (sc(isum_jdif) - sc(isum_jsum) + sc(idif_jdif) - sc(idif_jsum)) ./ 4;

	    % clean up memory
	    clear Gvx cc ss cs sc mvi nxi mvj nxj
	    clear idif isum jdif jsum idif_jdif idif_jsum isum_jdif isum_jsum

        else

	    Zvx = zeros(numel(mlay.vi), numel(nlay.xi));

        end

	% x-directed testing, y-directed source
        if numel(mlay.xi) && numel(nlay.yi)

	    Gxy=Gdx_flat.*Gdy_tri.*Gdx_tri.*Gdy_flat.*(Ne2.*kx.*ky.*Ze-Nm2.*ky.*kx.*Zm);

	    [ cc, ss ] = myfft(Gxy);

	    [ mxi, nyi ] = ndgrid(mlay.xi, nlay.yi);
	    [ mxj, nyj ] = ndgrid(mlay.xj, nlay.yj);

	    % y-position of x-directed bases (and x-position of y-directed) is the
	    % bottom/left edge (one with minimal x/y) - that is the reason for adding
	    % or subtracting wg.cnx/4 or wg.cny/4 (which corresponds to half-cell)
	    % Here for Zyx:
	    %  yt=mxj*dy+dy/2 (x-directed testing)
	    %  xs=nyi*dx+dx/2 (y-directed source)
	    idif = wrapidx((mxi-nyi)*wg.cnx/2 - wg.cnx/4 + 1, size(Gxy, 1)); % xt-xs
	    isum = wrapidx((mxi+nyi)*wg.cnx/2 + wg.cnx/4 + 1, size(Gxy, 1)); % xt+xs
	    jdif = wrapidx((mxj-nyj)*wg.cny/2 + wg.cny/4 + 1, size(Gxy, 2)); % yt-ys
	    jsum = wrapidx((mxj+nyj)*wg.cny/2 + wg.cny/4 + 1, size(Gxy, 2)); % yt+ys

	    idif_jdif = sub2ind(size(ss), idif, jdif);
	    idif_jsum = sub2ind(size(ss), idif, jsum);
	    isum_jdif = sub2ind(size(ss), isum, jdif);
	    isum_jsum = sub2ind(size(ss), isum, jsum);

	    Zxy = (-ss(idif_jsum) - ss(idif_jdif) + ss(isum_jsum) + ss(isum_jdif)) ./ 4;

	    % clean up memory
	    clear Gxy cc ss mxi nyi mxj nyj
	    clear idif isum jdif jsum idif_jdif idif_jsum isum_jdif isum_jsum

        else

	    Zxy = zeros(numel(mlay.xi), numel(nlay.yi));

        end

	% y-directed testing, y-directed source
        if numel(mlay.yi) && numel(nlay.yi)

	    Gyy=Gdx_flat.*Gdy_tri.*Gdx_flat.*Gdy_tri.*(-Ne2.*kx.*kx.*Ze-Nm2.*ky.*ky.*Zm);

	    [ cc, ss ] = myfft(Gyy);

	    [ myi, nyi ] = ndgrid(mlay.yi, nlay.yi);
	    [ myj, nyj ] = ndgrid(mlay.yj, nlay.yj);

	    % notice one is added to myi+nyi when computing isum - x-center of
	    % the y-directed basis is found as i*dx+dx/2, (i is the mesh index)
	    % the two halves added together give one
	    idif = wrapidx((myi-nyi)*wg.cnx/2+1, size(Gyy, 1));   % xt-xs
	    isum = wrapidx((myi+nyi+1)*wg.cnx/2+1, size(Gyy, 1)); % xt+xs
	    jdif = wrapidx((myj-nyj)*wg.cny/2+1, size(Gyy, 2));   % yt-ys
	    jsum = wrapidx((myj+nyj)*wg.cny/2+1, size(Gyy, 2));   % yt+ys

	    idif_jdif = sub2ind(size(cc), idif, jdif);
	    idif_jsum = sub2ind(size(cc), idif, jsum);
	    isum_jdif = sub2ind(size(cc), isum, jdif);
	    isum_jsum = sub2ind(size(cc), isum, jsum);

	    Zyy = (cc(idif_jdif) + cc(idif_jsum) - cc(isum_jdif) - cc(isum_jsum)) ./ 4;

	    % clean up memory
	    clear Gyy cc ss myi nyi myj nyj
	    clear idif isum jdif jsum idif_jdif idif_jsum isum_jdif isum_jsum

        else

	    Zyy = zeros(numel(mlay.yi), numel(nlay.yi));

        end

	% z-directed (via) testing, y-directed source
        if numel(mlay.vi) && numel(nlay.yi)

	    m = kc2./(j*freq*weps(mpos));
	    Gvy = Nm2.*ky.*Gdx_flat.*Gdy_tri.*Gdx_flat.*Gdy_flat.*m.*iii;

	    [ cc, ss, cs, sc ] = myfft(Gvy);

	    [ mvi, nyi ] = ndgrid(mlay.vi, nlay.yi);
	    [ mvj, nyj ] = ndgrid(mlay.vj, nlay.yj);

	    % y-position of x-directed bases (and x-position of y-directed) is the
	    % bottom/left edge (one with minimal x/y), x- and y-positions of the
	    % via is the bottom left corner (with minimal x/y) - that is the reason
	    % for adding or subtracting wg.cnx/4 or wg.cny/4 (which corresponds to
	    % half-cell)
	    % Here for Zvy:
	    %  xt=mvi*dx+dx/2 (z-directed (via) testing)
	    %  yt=mvj*dy+dy/2 (z-directed (via) testing)
	    %  xs=nyi*dx+dx/2 (y-directed source)
	    idif = wrapidx((mvi-nyi)*wg.cnx/2            + 1, size(Gvy, 1)); % xt-xs
	    isum = wrapidx((mvi+nyi)*wg.cnx/2 + wg.cnx/2 + 1, size(Gvy, 1)); % xt+xs
	    jdif = wrapidx((mvj-nyj)*wg.cny/2 + wg.cny/4 + 1, size(Gvy, 2)); % yt-ys
	    jsum = wrapidx((mvj+nyj)*wg.cny/2 + wg.cny/4 + 1, size(Gvy, 2)); % yt+ys

	    idif_jdif = sub2ind(size(cs), idif, jdif);
	    idif_jsum = sub2ind(size(cs), idif, jsum);
	    isum_jdif = sub2ind(size(cs), isum, jdif);
	    isum_jsum = sub2ind(size(cs), isum, jsum);

	    Zvy = viac * (cs(idif_jsum) + cs(idif_jdif) - cs(isum_jsum) - cs(isum_jdif)) ./ 4;

	    % clean up memory
	    clear Gvy cc ss cs sc mvi nyi mvj nyj
	    clear idif isum jdif jsum idif_jdif idif_jsum isum_jdif isum_jsum

        else

	    Zvy = zeros(numel(mlay.vi), numel(nlay.yi));

        end

        % Voltage at observation z due to equivalent voltage source of the via
	vvd = reshape(calc_vvd(tlm, z(mpos), mpos, npos), maxm, maxn);

	% x-directed testing, z-directed (via) source
        if numel(mlay.xi) && numel(nlay.vi)

	    m = kc2./(j*freq*weps(npos));
	    Gxv = -Nm2.*Gdx_flat.*Gdy_flat.*kx.*Gdx_tri.*Gdy_flat.*m.*vvd;

	    [ cc, ss, cs, sc ] = myfft(Gxv);

	    [ mxi, nvi ] = ndgrid(mlay.xi, nlay.vi);
	    [ mxj, nvj ] = ndgrid(mlay.xj, nlay.vj);

	    % See comments above (Zvy for example) for details about the indices
	    % evaluation. Briefly, wg.cnx/4 and wg.cny/4 corresponds to half-cell.
	    % Soource and observation centerpoint coordinates for Zxv:
	    %  xt=mvi*dx      (x-directed testing)
	    %  yt=mvj*dy+dy/2 (x-directed testing)
	    %  xs=nvi*dx+dx/2 (z-directed (via) source)
	    %  ys=nvj*dy+dy/2 (z-directed (via) source)
	    idif = wrapidx((mxi-nvi)*wg.cnx/2 - wg.cnx/4 + 1, size(Gxv, 1)); % xt-xs
	    isum = wrapidx((mxi+nvi)*wg.cnx/2 + wg.cnx/4 + 1, size(Gxv, 1)); % xt+xs
	    jdif = wrapidx((mxj-nvj)*wg.cny/2            + 1, size(Gxv, 2)); % yt-ys
	    jsum = wrapidx((mxj+nvj)*wg.cny/2 + wg.cny/2 + 1, size(Gxv, 2)); % yt+ys

	    idif_jdif = sub2ind(size(sc), idif, jdif);
	    idif_jsum = sub2ind(size(sc), idif, jsum);
	    isum_jdif = sub2ind(size(sc), isum, jdif);
	    isum_jsum = sub2ind(size(sc), isum, jsum);

	    Zxv = viac * (sc(isum_jdif) - sc(isum_jsum) - sc(idif_jdif) + sc(idif_jsum)) ./ 4;

	    % clean up memory
	    clear Gxv cc ss cs sc mxi nvi mxj nvj
	    clear idif isum jdif jsum idif_jdif idif_jsum isum_jdif isum_jsum

        else

	    Zxv = zeros(numel(mlay.xi), numel(nlay.vi));

        end

	% y-directed testing, z-directed (via) source
        if numel(mlay.yi) && numel(nlay.vi)

	    m = kc2./(j*freq*weps(npos));
	    Gyv = -Nm2.*ky.*Gdx_flat.*Gdy_tri.*Gdx_flat.*Gdy_flat.*m.*vvd;

	    [ cc, ss, cs, sc ] = myfft(Gyv);

	    [ myi, nvi ] = ndgrid(mlay.yi, nlay.vi);
	    [ myj, nvj ] = ndgrid(mlay.yj, nlay.vj);

	    % See comments above (Zvy for example) for details about the indices
	    % evaluation. Briefly, wg.cnx/4 and wg.cny/4 correspond to half-cell.
	    % Soource and observation centerpoint coordinates for Zyv:
	    %  xt=mvi*dx+dy/2 (y-directed testing)
	    %  yt=mvj*dy      (y-directed testing)
	    %  xs=nvi*dx+dx/2 (z-directed (via) source)
	    %  ys=nvj*dy+dy/2 (z-directed (via) source)
	    idif = wrapidx((myi-nvi)*wg.cnx/2            + 1, size(Gyv, 1)); % xt-xs
	    isum = wrapidx((myi+nvi)*wg.cnx/2 + wg.cnx/2 + 1, size(Gyv, 1)); % xt+xs
	    jdif = wrapidx((myj-nvj)*wg.cny/2 - wg.cny/4 + 1, size(Gyv, 2)); % yt-ys
	    jsum = wrapidx((myj+nvj)*wg.cny/2 + wg.cny/4 + 1, size(Gyv, 2)); % yt+ys

	    idif_jdif = sub2ind(size(cs), idif, jdif);
	    idif_jsum = sub2ind(size(cs), idif, jsum);
	    isum_jdif = sub2ind(size(cs), isum, jdif);
	    isum_jsum = sub2ind(size(cs), isum, jsum);

	    Zyv = viac * (cs(idif_jsum) - cs(idif_jdif) - cs(isum_jsum) + cs(isum_jdif)) ./ 4;

	    % clean up memory
	    clear Gyv cc ss cs sc myi nvi myj nvj
	    clear idif isum jdif jsum idif_jdif idif_jsum isum_jdif isum_jsum

        else

	    Zyv = zeros(numel(mlay.yi), numel(nlay.vi));

        end

	% z-directed testing, z-directed (via) source
        if numel(mlay.vi) && numel(nlay.vi)

	    m = -kc2.*kc2/(freq*weps(npos)*freq*weps(mpos));
	    iivd = calc_iivd(tlm, mpos, npos);
	    r = reshape(iivd, maxm, maxn);

	    Gvv = Nm2.*Gdx_flat.*Gdy_flat.*Gdx_flat.*Gdy_flat.*m.*r;

            % see calczmn.m for details on via self-reaction calculations
	    if mpos == npos
	        m = -h(npos)*kc2/(j*freq*weps(npos));
	        Gvv = Gvv + Nm2.*Gdx_flat.*Gdy_flat.*Gdx_flat.*Gdy_flat.*m;
	    end

	    [ cc, ss, cs, sc ] = myfft(Gvv);

	    [ mvi, nvi ] = ndgrid(mlay.vi, nlay.vi);
	    [ mvj, nvj ] = ndgrid(mlay.vj, nlay.vj);

	    % See comments above (Zvy for example) for details about the indices
	    % evaluation. Briefly, wg.cnx/4 and wg.cny/4 correspond to half-cell.
	    % Soource and observation centerpoint coordinates for Zvv:
	    %  xt=mvi*dx+dy/2 (z-directed (via) testing)
	    %  yt=mvj*dy+dy/2 (z-directed (via) testing)
	    %  xs=nvi*dx+dx/2 (z-directed (via) source)
	    %  ys=nvj*dy+dy/2 (z-directed (via) source)
	    idif = wrapidx((mvi-nvi)*wg.cnx/2            + 1, size(Gvv, 1)); % xt-xs
	    isum = wrapidx((mvi+nvi)*wg.cnx/2 + wg.cnx/2 + 1, size(Gvv, 1)); % xt+xs
	    jdif = wrapidx((mvj-nvj)*wg.cny/2            + 1, size(Gvv, 2)); % yt-ys
	    jsum = wrapidx((mvj+nvj)*wg.cny/2 + wg.cny/2 + 1, size(Gvv, 2)); % yt+ys

	    idif_jdif = sub2ind(size(cc), idif, jdif);
	    idif_jsum = sub2ind(size(cc), idif, jsum);
	    isum_jdif = sub2ind(size(cc), isum, jdif);
	    isum_jsum = sub2ind(size(cc), isum, jsum);

	    Zvv = viac2 * (cc(idif_jdif) - cc(idif_jsum) - cc(isum_jdif) + cc(isum_jsum)) ./ 4;

	    % clean up memory
	    clear m iivd r Gvv cc ss cs sc mvi nvi mvj nvj
	    clear idif isum jdif jsum idif_jdif idif_jsum isum_jdif isum_jsum

        else

	    Zvv = zeros(numel(mlay.vi), numel(nlay.vi));

        end
	
	% compose the entire matrix block for this pair of layers
	Zl = [ Zxx Zxy Zxv ; Zyx Zyy Zyv ; Zvx Zvy Zvv ];

	clear Zxx Zxy Zxv Zyx Zyy Zyv Zvx Zvy Zvv

	% Identify segments which cross the waveguide boundary - the
	% corresponding elements of the Z matrix need to be multiplied by 0.5
	% The source segmetns which cross:
	mxmul=-(~mlay.xi | ~(mlay.xi-wg.nx))*0.5+1.0;
	mymul=-(~mlay.yj | ~(mlay.yj-wg.ny))*0.5+1.0;
	mvmul = mlay.vi*0 + 1.0; % vias can not cross the boundary
	Mm=diag([ mxmul(:) ; mymul(:) ; mvmul(:) ]);

	% And the observation segmetns which cross:
	nxmul=-(~nlay.xi | ~(nlay.xi-wg.nx))*0.5+1.0;
	nymul=-(~nlay.yj | ~(nlay.yj-wg.ny))*0.5+1.0;
	nvmul = nlay.vi*0 + 1.0; % vias can not cross the boundary
	Mn=diag([ nxmul(:) ; nymul(:) ; nvmul(:) ]);

	% scale the impedance matrix elements for the boundary-crossing segments
	Zl=Mm*Zl*Mn;

	clear Mm Mn

	% And, finally, put this block into the overall matrix
	Z(cumbf(mli)+1:cumbf(mli+1), cumbf(nli)+1:cumbf(nli+1)) = Zl;

    end
end
