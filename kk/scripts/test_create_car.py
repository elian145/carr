import sys, os
sys.path.append(os.path.dirname(__file__) + '/..')

import app_new as app_module  # type: ignore
from models import db, User, Car  # type: ignore


def main() -> None:
	app = app_module.app
	with app.app_context():
		db.create_all()
		u = User.query.filter_by(email='elianyaqoob1005@gmail.com').first()
		if not u:
			print('NO_USER')
			return
		try:
			car = Car(
				seller_id=u.id,
				title='Testbrand Testmodel 2022',
				title_status='active',
				brand='testbrand',
				model='testmodel',
				year=2022,
				mileage=0,
				engine_type='gasoline',
				transmission='automatic',
				drive_type='fwd',
				condition='used',
				body_type='sedan',
				price=1.0,
				location='erbil',
			)
			db.session.add(car)
			db.session.commit()
			print('CREATE_OK', car.id, car.public_id)
		except Exception as e:
			import traceback
			print('CREATE_ERR', str(e))
			print(traceback.format_exc())


if __name__ == '__main__':
	main()


