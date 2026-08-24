const FaceService = require('../face/faceService');
const PlacesService = require('../places/placesService');
const tableConfig = require('../../../../db/table/tableConfig');

async function getEnableByKey(key) {
  try {
    const raw = await tableConfig.getConfigByKey(key);
    return raw === '1' ? 1 : 0;
  } catch (_) {
    return 0;
  }
}

class AppAiService {
  constructor(knex) {
    this.knex = knex;
  }

  async getOverview(params = {}) {
    const limit = Math.max(1, Math.min(50, Number(params.limit) || 20));
    const locale = params && params.locale ? String(params.locale) : 'zh-CN';
    const validPaths =
      params.validPaths !== undefined ? (Array.isArray(params.validPaths) ? params.validPaths.filter(Boolean) : []) : undefined;

    const [faceEnable, placeEnable, similarEnable] = await Promise.all([getEnableByKey('ai_face_enable'), getEnableByKey('ai_place_enable'), getEnableByKey('ai_similar_enable')]);

    const faceParams = { page: 1, pageSize: limit, status: 'visiable', ...(validPaths !== undefined ? { validPaths } : {}) };
    const facesPromise =
      faceEnable === 1
        ? new FaceService(this.knex).listFaces(faceParams)
        : Promise.resolve({
            items: [],
            pagination: { total: 0, page: 1, pageSize: limit },
          });

    const sceneParams = { status: 'visible', locale, ...(validPaths !== undefined ? { validPaths } : {}) };
    const scenesPromise =
      placeEnable === 1
        ? new PlacesService(this.knex).listPlaces(sceneParams)
        : Promise.resolve({
            items: [],
            pagination: { total: 0, page: 1, pageSize: limit },
          });

    const [facesRaw, scenesRaw] = await Promise.all([facesPromise, scenesPromise]);

    const faces = {
      faceEnable,
      items: Array.isArray(facesRaw && facesRaw.items) ? facesRaw.items : [],
      pagination: facesRaw && facesRaw.pagination ? facesRaw.pagination : { total: 0, page: 1, pageSize: limit },
    };

    const scenesAllItems = Array.isArray(scenesRaw && scenesRaw.items) ? scenesRaw.items : [];
    const scenes = {
      placeEnable,
      items: scenesAllItems.slice(0, limit),
      pagination: scenesRaw && scenesRaw.pagination ? { ...scenesRaw.pagination, pageSize: limit } : { total: 0, page: 1, pageSize: limit },
    };

    return {
      faces,
      scenes,
      similarEnable,
    };
  }
}

module.exports = AppAiService;
