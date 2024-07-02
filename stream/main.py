from dateutil.parser import parse as parse_date
import faust
import logging


class ExpediaRecord(faust.Record):
    id: float
    date_time: str
    site_name: int
    posa_container: int
    user_location_country: int
    user_location_region: int
    user_location_city: int
    orig_destination_distance: float
    user_id: int
    is_mobile: int
    is_package: int
    channel: int
    srch_ci: str
    srch_co: str
    srch_adults_cnt: int
    srch_children_cnt: int
    srch_rm_cnt: int
    srch_destination_id: int
    srch_destination_type_id: int
    hotel_id: int


class ExpediaExtRecord(ExpediaRecord):
    stay_category: str


logger = logging.getLogger(__name__)
app = faust.App("kafkastreams", broker="kafka://kafka:9092")
source_topic = app.topic("expedia", value_type=ExpediaRecord)
destination_topic = app.topic("expedia_ext", value_type=ExpediaExtRecord)


def categorize_stay(srch_ci, srch_co):
    if srch_ci is None or srch_co is None:
        return "Erroneous data"
    try:
        check_in = parse_date(srch_ci)
        check_out = parse_date(srch_co)
        stay_duration = (check_out - check_in).days

        logger.info(f"Got new stay_duration={stay_duration}")

        if stay_duration <= 0:
            return "Erroneous data"
        elif stay_duration <= 4:
            return "Short stay"
        elif stay_duration <= 10:
            return "Standard stay"
        elif stay_duration <= 14:
            return "Standard extended stay"
        else:
            return "Long stay"
    except Exception as e:
        logger.error(f"Error parsing dates: {e}")
        return "Erroneous data"


@app.agent(source_topic, sink=[destination_topic])
async def handle(messages):
    async for message in messages:
        if message is None:
            logger.info("No messages")
            continue

        stay_category = categorize_stay(message.srch_ci, message.srch_co)
        data = message.asdict()
        yield ExpediaExtRecord(**data, stay_category=stay_category)


if __name__ == "__main__":
    app.main()
