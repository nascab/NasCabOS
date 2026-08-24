const photoTimeLineService = require('./photoTimeLineService');
const Logger = require('../../../../utils/logger');
const ResponseUtil = require('../../../apiUtils/responseUtil');
const photoMapService = require('../map/photoMapService');

class PhotoTimeLineController {
  async getPhotoTotalCount(req, res) {
    try {
      const { sourceList, collection_id } = req.body || {};
      const result = await photoTimeLineService.getVisiblePhotoTotalCount(
        {
          sourceList,
          collection_id,
        },
        req.user
      );
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('getPhotoTotalCount error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async getTimelineYearList(req, res) {
    try {
      const result = await photoTimeLineService.getTimelineYearList(req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('getTimelineYearList error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  /**
   * 获取时间轴日期列表
   */
  async getTimelineDateList(req, res) {
    try {
      const { sort, fileType, search, geohash, sourceList, list_type, album_id, collection_id, smart_album_id, loadTheDay, face_id, place_name, year } = req.body;
      const result = await photoTimeLineService.getTimelineDateList(
        {
          sort,
          fileType,
          search,
          geohash,
          sourceList,
          list_type,
          album_id,
          collection_id,
          smart_album_id,
          loadTheDay,
          face_id: face_id,
          place_name: place_name,
          year,
        },
        req.user
      );
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('getTimelineDateList error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  /**
   * 获取时间轴照片列表
   */
  async getTimelinePhotoList(req, res) {
    try {
      // 参数: page, pageSize, fileType,original_time,
      // sort: 'asc' | 'desc' 数据根据original_time的排序方式
      // dataTimeType(1为获取时间戳originalTime之前的(包含时间戳),2为获取时间戳originalTime之后的)
      const { pageSize, sort, fileType, originalTime, startTime, endTime, search, geohash, sourceList, list_type, album_id, collection_id, smart_album_id, loadTheDay, face_id, place_name, year } =
        req.body;

      const result = await photoTimeLineService.getTimelinePhotoList(
        {
          pageSize,
          sort,
          fileType,
          originalTime,
          startTime,
          endTime,
          search,
          geohash,
          sourceList,
          list_type,
          album_id,
          collection_id,
          smart_album_id,
          loadTheDay,
          face_id: face_id,
          place_name: place_name,
          year,
        },
        req.user
      );

      const photoList = Array.isArray(result) ? result : [];

      let locale = '';
      try {
        locale = typeof req.getLocale === 'function' ? String(req.getLocale() || '') : '';
      } catch (_) {
        locale = '';
      }

      const dateOrder = [];
      const dateToMeta = new Map();
      const maxPerDate = 3;

      for (const row of photoList) {
        const date = row && row.original_date ? String(row.original_date).trim() : '';
        if (!date) continue;

        let meta = dateToMeta.get(date);
        if (!meta) {
          meta = { geohash5List: [], geohash5Set: new Set(), cameraList: [], cameraSet: new Set() };
          dateToMeta.set(date, meta);
          dateOrder.push(date);
        }

        const rawGeohash5 = row && row.geohash5 ? String(row.geohash5).trim() : '';
        const fallbackGeohash = row && row.geohash ? String(row.geohash).trim() : '';
        const geohash5 = rawGeohash5 || (fallbackGeohash ? fallbackGeohash.slice(0, 5) : '');
        if (geohash5 && meta.geohash5List.length < maxPerDate && !meta.geohash5Set.has(geohash5)) {
          meta.geohash5Set.add(geohash5);
          meta.geohash5List.push(geohash5);
        }

        const camera = row && row.camera ? String(row.camera).trim() : '';
        if (camera && meta.cameraList.length < maxPerDate && !meta.cameraSet.has(camera)) {
          meta.cameraSet.add(camera);
          meta.cameraList.push(camera);
        }
      }

      const allGeohash5 = [];
      const geohash5Seen = new Set();
      for (const [, meta] of dateToMeta.entries()) {
        for (const h of meta.geohash5List) {
          if (!h || geohash5Seen.has(h)) continue;
          geohash5Seen.add(h);
          allGeohash5.push(h);
        }
      }

      const geohash5ToGeo = new Map();
      await Promise.all(
        allGeohash5.map(async h => {
          const geo = await photoMapService.getLocationStr({ dbGeo: req.dbGeo, locale }, h);
          geohash5ToGeo.set(h, geo || '');
        })
      );

      const dateInfoList = dateOrder.map(date => {
        const meta = dateToMeta.get(date);
        const geoList = [];
        const geoSet = new Set();
        if (meta && Array.isArray(meta.geohash5List)) {
          for (const h of meta.geohash5List) {
            const geo = geohash5ToGeo.get(h) || '';
            const g = geo.trim();
            if (!g || geoSet.has(g)) continue;
            geoSet.add(g);
            geoList.push(g);
          }
        }
        return {
          original_date: date,
          geo: geoList.join('、'),
          camera: meta && Array.isArray(meta.cameraList) ? meta.cameraList.join('、') : '',
        };
      });

      return ResponseUtil.success(req, res, { photoList, dateInfoList }, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('getTimelinePhotoList error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  /**
   * 批量收藏/取消收藏
   */
  async batchFavorite(req, res) {
    try {
      const { file_hashes, is_favorite } = req.body;
      if (!Array.isArray(file_hashes)) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR');
      }
      await photoTimeLineService.batchFavorite(req.user, file_hashes, is_favorite);
      return ResponseUtil.success(req, res, null, 'common.SUCCESS');
    } catch (error) {
      Logger.error('batchFavorite error:', error);
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', 500);
    }
  }

  /**
   * 切换收藏状态
   */
  async toggleFavorite(req, res) {
    try {
      const { file_hash } = req.body;
      if (!file_hash) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR');
      }
      const result = await photoTimeLineService.toggleFavorite(req.user, file_hash);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('toggleFavorite error:', error);
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', 500);
    }
  }

  /**
   * 批量将照片放入回收站
   */
  async batchTrash(req, res) {
    try {
      const { ids } = req.body;
      if (!Array.isArray(ids)) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR');
      }
      await photoTimeLineService.batchTrash(ids, true, req.user);
      return ResponseUtil.success(req, res, null, 'photo.TRASH_ADD_SUCCESS', 200);
    } catch (error) {
      Logger.error('batchTrash error:', error);
      const statusCode = error.statusCode || 500;
      const message = statusCode === 403 ? 'auth.PERMISSION_DENIED' : (error.message || 'common.ERROR');
      return ResponseUtil.error(req, res, message, statusCode);
    }
  }

  /**
   * 获取回收站内的照片列表
   */
  async getTrashPhotoList(req, res) {
    try {
      const { page, pageSize, fileType, search, sortField, sortOrder } = req.body;
      const result = await photoTimeLineService.getTrashPhotoList(
        {
          page,
          pageSize,
          fileType,
          search,
          sortField,
          sortOrder,
        },
        req.user
      );
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('getTrashPhotoList error:', error);
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', 500);
    }
  }

  /**
   * 从回收站中恢复照片
   */
  async restoreFromTrash(req, res) {
    try {
      const { ids, restore_all } = req.body || {};
      if (restore_all) {
        await photoTimeLineService.restoreAllFromTrash(req.user);
        return ResponseUtil.success(req, res, null, 'photo.TRASH_RESTORE_SUCCESS', 200);
      }
      if (!Array.isArray(ids)) return ResponseUtil.error(req, res, 'common.PARAM_ERROR');
      await photoTimeLineService.restoreFromTrash(ids);
      return ResponseUtil.success(req, res, null, 'photo.TRASH_RESTORE_SUCCESS', 200);
    } catch (error) {
      Logger.error('restoreFromTrash error:', error);
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', 500);
    }
  }

  /**
   * 从回收站中删除（物理删除）
   */
  async deleteFromTrash(req, res) {
    try {
      const { ids, recycle = false, delete_livephoto_file = 0, delete_raw_file = 0 } = req.body;
      if (!Array.isArray(ids)) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR');
      }
      await photoTimeLineService.deleteFromTrash(ids, recycle, req.user, {
        deleteLivePhotoFile: delete_livephoto_file,
        deleteRawFile: delete_raw_file,
      });
      return ResponseUtil.success(req, res, null, 'photo.TRASH_DELETE_SUCCESS', 200);
    } catch (error) {
      Logger.error('deleteFromTrash error:', error);
      const statusCode = error.statusCode || 500;
      const message = statusCode === 403 ? 'auth.PERMISSION_DENIED' : (error.message || 'common.ERROR');
      return ResponseUtil.error(req, res, message, statusCode);
    }
  }

  /**
   * 清空回收站
   */
  async emptyTrash(req, res) {
    try {
      const { recycle = false, delete_livephoto_file = 0, delete_raw_file = 0 } = req.body;
      await photoTimeLineService.emptyTrash(req.user, recycle, {
        deleteLivePhotoFile: delete_livephoto_file,
        deleteRawFile: delete_raw_file,
      });
      return ResponseUtil.success(req, res, null, 'photo.TRASH_EMPTY_SUCCESS', 200);
    } catch (error) {
      Logger.error('emptyTrash error:', error);
      const statusCode = error.statusCode || 500;
      const message = statusCode === 403 ? 'auth.PERMISSION_DENIED' : (error.message || 'common.ERROR');
      return ResponseUtil.error(req, res, message, statusCode);
    }
  }

  async getBoundsPhoto(req, res) {
    try {
      const { minLat, minLng, maxLat, maxLng, zoom, fileType, search, sourceList, list_type, album_id, collection_id, smart_album_id, loadTheDay, maxReturnCount } = req.body || {};
      const result = await photoTimeLineService.getBoundsPhoto(
        {
          minLat,
          minLng,
          maxLat,
          maxLng,
          zoom,
          fileType,
          search,
          sourceList,
          list_type,
          album_id,
          collection_id,
          smart_album_id,
          loadTheDay,
          maxReturnCount,
        },
        req.user
      );
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('getBoundsPhoto error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }
}

module.exports = new PhotoTimeLineController();
