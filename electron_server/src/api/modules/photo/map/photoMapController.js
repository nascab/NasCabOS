const ResponseUtil = require('../../../apiUtils/responseUtil');
const photoMapService = require('./photoMapService');

function parseTileServerFromBody(body) {
  const b = body || {};
  if (b.tileServer && typeof b.tileServer === 'object') return b.tileServer;
  if (typeof b.tileServerJson === 'string' && b.tileServerJson.trim()) {
    try {
      return JSON.parse(b.tileServerJson);
    } catch (_) {
      return null;
    }
  }
  if (b.tileServerJson && typeof b.tileServerJson === 'object') return b.tileServerJson;
  return null;
}

class PhotoMapController {
  async tile(req, res) {
    const { zoom, x, y } = req.query || {};
    if (zoom === undefined || x === undefined || y === undefined) {
      return res.status(404).end();
    }
    const filePath = await photoMapService.ensureTileCached({ zoom, x, y });
    if (!filePath) return res.status(404).end();
    res.set('Content-Type', 'image/png');
    return res.sendFile(filePath);
  }

  async getZoom(req, res) {
    try {
      const data = await photoMapService.getZoomInfo();
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async getTileServerList(req, res) {
    try {
      const list = await photoMapService.getTileServerList();
      return ResponseUtil.success(req, res, { tileServerList: list }, 'common.SUCCESS', 200);
    } catch (e) {
      console.log(e);
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async setTileServer(req, res) {
    try {
      const tileServer = parseTileServerFromBody(req.body);
      await photoMapService.setTileServer(tileServer);
      return ResponseUtil.success(req, res, true, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async addTileServer(req, res) {
    try {
      const tileServer = parseTileServerFromBody(req.body);
      await photoMapService.addTileServer(tileServer);
      return ResponseUtil.success(req, res, true, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async deleteTileServer(req, res) {
    try {
      const tileServer = parseTileServerFromBody(req.body);
      await photoMapService.deleteTileServer(tileServer);
      return ResponseUtil.success(req, res, true, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async getLocationStr(req, res) {
    try {
      const { geohash } = req.body || {};
      let locale = '';
      try {
        locale = typeof req.getLocale === 'function' ? String(req.getLocale() || '') : '';
      } catch (_) {
        locale = '';
      }
      const geo = await photoMapService.getLocationStr({ dbGeo: req.dbGeo, locale }, geohash);
      return ResponseUtil.success(req, res, { geo }, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async getBoundsPhoto(req, res) {
    try {
      const result = await photoMapService.getBoundsPhoto({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async getAlbumPhotoForMap(req, res) {
    try {
      const result = await photoMapService.getAlbumPhotoForMap({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }
}

module.exports = new PhotoMapController();
